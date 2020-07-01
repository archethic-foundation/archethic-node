defmodule UnirisCore.P2PServer do
  @moduledoc false
  require Logger

  use GenServer

  alias UnirisCore.Transaction
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.P2P
  alias UnirisCore.Election
  alias UnirisCore.Mining
  alias UnirisCore.Crypto
  alias UnirisCore.TaskSupervisor
  alias UnirisCore.PubSub
  alias UnirisCore.Beacon
  alias UnirisCore.Storage

  alias UnirisCore.P2P.Message
  alias UnirisCore.P2P.Message.GetBootstrappingNodes
  alias UnirisCore.P2P.Message.GetStorageNonce
  alias UnirisCore.P2P.Message.ListNodes
  alias UnirisCore.P2P.Message.GetTransaction
  alias UnirisCore.P2P.Message.GetTransactionChain
  alias UnirisCore.P2P.Message.GetUnspentOutputs
  alias UnirisCore.P2P.Message.NewTransaction
  alias UnirisCore.P2P.Message.StartMining
  alias UnirisCore.P2P.Message.GetProofOfIntegrity
  alias UnirisCore.P2P.Message.AddContext
  alias UnirisCore.P2P.Message.CrossValidate
  alias UnirisCore.P2P.Message.CrossValidationDone
  alias UnirisCore.P2P.Message.ReplicateTransaction
  alias UnirisCore.P2P.Message.AcknowledgeStorage
  alias UnirisCore.P2P.Message.AddNodeInfo
  alias UnirisCore.P2P.Message.GetBalance
  alias UnirisCore.P2P.Message.GetLastTransaction
  alias UnirisCore.P2P.Message.GetBeaconSlots
  alias UnirisCore.P2P.Message.BootstrappingNodes
  alias UnirisCore.P2P.Message.NodeList
  alias UnirisCore.P2P.Message.TransactionList
  alias UnirisCore.P2P.Message.Ok
  alias UnirisCore.P2P.Message.NotFound
  alias UnirisCore.P2P.Message.BeaconSlotList
  alias UnirisCore.P2P.Message.Balance
  alias UnirisCore.P2P.Message.UnspentOutputList
  alias UnirisCore.P2P.Message.ProofOfIntegrity
  alias UnirisCore.P2P.Message.GetTransactionHistory
  alias UnirisCore.P2P.Message.GetTransactionInputs
  alias UnirisCore.P2P.Message.TransactionHistory
  alias UnirisCore.P2P.Message.EncryptedStorageNonce
  alias UnirisCore.Transaction

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    port = Keyword.get(opts, :port)

    {:ok, listen_socket} =
      :gen_tcp.listen(port, [:binary, {:packet, 4}, {:active, false}, {:reuseaddr, true}])

    Logger.info("P2P Server running on port #{port}")

    Enum.each(0..10, fn _ ->
      Task.Supervisor.start_child(TaskSupervisor, fn -> loop_acceptor(listen_socket) end)
    end)

    {:ok, []}
  end

  def loop_acceptor(listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        {address, _port} = parse_socket(socket)

        {:ok, _pid} =
          Task.Supervisor.start_child(TaskSupervisor, fn -> recv_loop(socket, address) end)

        loop_acceptor(listen_socket)

      {:error, reason} ->
        Logger.info("TCP connection failed: #{reason}")
    end
  end

  def recv_loop(socket, address) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, data} ->
        result =
          data
          |> Message.decode()
          |> process_message()
          |> Message.encode()
          |> Message.wrap_binary()

        :gen_tcp.send(socket, result)
        recv_loop(socket, address)

      {:error, :closed} ->
        :gen_tcp.close(socket)

      {:error, :enotconn} ->
        :gen_tcp.close(socket)
    end
  end

  defp parse_socket(socket) do
    {:ok, {addr, port}} = :inet.peername(socket)
    {addr, port}
  end

  defp process_message(%GetBootstrappingNodes{patch: patch}) do
    top_nodes =
      P2P.list_nodes()
      |> Enum.filter(&(&1.authorized? && &1.available?))

    closest_nodes =
      top_nodes
      |> P2P.nearest_nodes(patch)
      |> Enum.take(5)

    %BootstrappingNodes{
      new_seeds: Enum.take_random(top_nodes, 5),
      closest_nodes: closest_nodes
    }
  end

  defp process_message(%GetStorageNonce{public_key: public_key}) do
    case loop_node_info(public_key, DateTime.utc_now()) do
      {:ok, node_public_key} ->
        %EncryptedStorageNonce{
          digest: Crypto.encrypt_storage_nonce(node_public_key)
        }
    end
  end

  defp process_message(%ListNodes{}) do
    %NodeList{
      nodes: P2P.list_nodes()
    }
  end

  defp process_message(%NewTransaction{transaction: tx}) do
    welcome_node = Crypto.node_public_key()
    validation_nodes = Election.validation_nodes(tx) |> Enum.map(& &1.last_public_key)

    Enum.each(validation_nodes, fn node ->
      Task.Supervisor.start_child(TaskSupervisor, fn ->
        P2P.send_message(node, %StartMining{
          transaction: tx,
          welcome_node_public_key: welcome_node,
          validation_node_public_keys: validation_nodes
        })
      end)
    end)

    %Ok{}
  end

  defp process_message(%GetTransaction{address: tx_address}) do
    case Storage.get_transaction(tx_address) do
      {:ok, tx} ->
        tx

      _ ->
        %NotFound{}
    end
  end

  defp process_message(%GetTransactionChain{address: tx_address}) do
    %TransactionList{
      transactions: Storage.get_transaction_chain(tx_address)
    }
  end

  defp process_message(%GetUnspentOutputs{address: tx_address}) do
    %UnspentOutputList{
      unspent_outputs: Storage.get_unspent_outputs(tx_address)
    }
  end

  defp process_message(%GetProofOfIntegrity{address: tx_address}) do
    case Storage.get_transaction(tx_address) do
      {:ok, %Transaction{validation_stamp: %ValidationStamp{proof_of_integrity: poi}}} ->
        %ProofOfIntegrity{
          digest: poi
        }

      _ ->
        %NotFound{}
    end
  end

  defp process_message(%StartMining{
         transaction: tx,
         welcome_node_public_key: welcome_node_public_key,
         validation_node_public_keys: validation_nodes
       }) do
    {:ok, _} = Mining.start(tx, welcome_node_public_key, validation_nodes)
    %Ok{}
  end

  defp process_message(%GetTransactionHistory{address: tx_address}) do
    %TransactionHistory{
      transaction_chain: Storage.get_transaction_chain(tx_address),
      unspent_outputs: Storage.get_unspent_outputs(tx_address)
    }
  end

  defp process_message(%AddContext{
         address: tx_address,
         validation_node_public_key: validation_node,
         context: context
       }) do
    :ok =
      Mining.add_context(
        tx_address,
        validation_node,
        context
      )

    %Ok{}
  end

  defp process_message(%ReplicateTransaction{transaction: tx}) do
    :ok = Mining.replicate_transaction(tx)
    %Ok{}
  end

  defp process_message(%AcknowledgeStorage{address: tx_address}) do
    :ok = PubSub.notify_new_transaction(tx_address)
    %Ok{}
  end

  defp process_message(%CrossValidate{
         address: tx_address,
         validation_stamp: stamp,
         replication_tree: replication_tree
       }) do
    :ok = Mining.cross_validate(tx_address, stamp, replication_tree)
    %Ok{}
  end

  defp process_message(%CrossValidationDone{address: tx_address, cross_validation_stamp: stamp}) do
    :ok = Mining.add_cross_validation_stamp(tx_address, stamp)
    %Ok{}
  end

  defp process_message(%GetBeaconSlots{subsets_slots: subsets_slots}) do
    slots =
      subsets_slots
      |> Enum.map(&Map.to_list/1)
      |> Enum.map(fn [{subset, dates}] -> Beacon.previous_slots(subset, dates) end)
      |> Enum.flat_map(& &1)

    %BeaconSlotList{slots: slots}
  end

  defp process_message(%AddNodeInfo{subset: subset, node_info: node_info}) do
    :ok = Beacon.add_node_info(subset, node_info)
    %Ok{}
  end

  defp process_message(%GetLastTransaction{address: last_address}) do
    case UnirisCore.get_last_transaction(last_address) do
      {:ok, tx} ->
        tx

      _ ->
        %NotFound{}
    end
  end

  defp process_message(%GetBalance{address: address}) do
    %Balance{
      uco: Storage.balance(address)
    }
  end

  defp process_message(%GetTransactionInputs{address: address}) do
    %UnspentOutputList{
      unspent_outputs: Storage.get_inputs(address)
    }
  end

  defp loop_node_info(node_public_key, date) do
    case P2P.node_info(node_public_key) do
      {:ok, _} ->
        {:ok, node_public_key}

      _ ->
        if DateTime.diff(date, DateTime.utc_now()) <= 3 do
          loop_node_info(node_public_key, date)
        end
    end
  end
end
