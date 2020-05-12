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
  alias UnirisCore.BeaconSlot.NodeInfo
  alias UnirisCore.Storage

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
        # TODO: include safe binary decoding, disabled because unexpected error arguments. To resolve !
        result =
          data
          |> :erlang.binary_to_term()
          |> process_message

        :gen_tcp.send(socket, :erlang.term_to_binary(result))
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

  defp process_message(messages) when is_list(messages) do
    do_process_messages(messages, [])
  end

  defp process_message(:new_seeds) do
    P2P.list_nodes()
    |> Enum.filter(&(&1.authorized? && &1.available?))
    |> Enum.take_random(5)
  end

  defp process_message({:closest_nodes, network_patch}) do
    P2P.list_nodes()
    |> Enum.filter(&(&1.authorized? && &1.available?))
    |> P2P.nearest_nodes(network_patch)
    |> Enum.take(5)
  end

  defp process_message({:get_storage_nonce, node_public_key}) when is_binary(node_public_key) do
    loop_node_info(node_public_key, DateTime.utc_now())
  end

  defp process_message(:list_nodes) do
    P2P.list_nodes()
  end

  defp process_message({:new_transaction, tx = %Transaction{}}) do
    welcome_node = Crypto.node_public_key()
    validation_nodes = Election.validation_nodes(tx) |> Enum.map(& &1.last_public_key)

    Enum.each(validation_nodes, fn node ->
      Task.Supervisor.start_child(TaskSupervisor, fn ->
        P2P.send_message(node, {:start_mining, tx, welcome_node, validation_nodes})
      end)
    end)
  end

  defp process_message({:get_transaction, tx_address}) do
    Storage.get_transaction(tx_address)
  end

  defp process_message({:get_transaction_chain, tx_address}) do
    Storage.get_transaction_chain(tx_address)
  end

  defp process_message({:get_unspent_outputs, tx_address}) do
    Storage.get_unspent_output_transactions(tx_address)
  end

  defp process_message({:get_proof_of_integrity, tx_address}) do
    case Storage.get_transaction(tx_address) do
      {:ok, %Transaction{validation_stamp: %ValidationStamp{proof_of_integrity: poi}}} ->
        {:ok, poi}

      _ ->
        {:error, :transaction_not_exists}
    end
  end

  defp process_message(
         {:start_mining, tx = %Transaction{}, welcome_node_public_key, validation_nodes}
       ) do
    Mining.start(tx, welcome_node_public_key, validation_nodes)
  end

  defp process_message(
         {:add_context, tx_address, validation_node, previous_storage_nodes,
          validation_nodes_view, chain_storage_nodes_view, beacon_storage_nodes_view}
       ) do
    Mining.add_context(
      tx_address,
      validation_node,
      previous_storage_nodes,
      validation_nodes_view,
      chain_storage_nodes_view,
      beacon_storage_nodes_view
    )
  end

  defp process_message(
         {:replicate_chain,
          tx = %Transaction{
            validation_stamp: %ValidationStamp{},
            cross_validation_stamps: stamps
          }}
       )
       when is_list(stamps) and length(stamps) >= 0 do
    Mining.replicate_transaction_chain(tx)
  end

  defp process_message(
         {:replicate_transaction,
          tx = %Transaction{
            validation_stamp: %ValidationStamp{},
            cross_validation_stamps: stamps
          }}
       )
       when is_list(stamps) and length(stamps) >= 0 do
    Mining.replicate_transaction(tx)
  end

  defp process_message({:replicate_address, tx = %Transaction{}}) do
    Mining.replicate_address(tx)
  end

  defp process_message({:acknowledge_storage, tx_address}) when is_binary(tx_address) do
    PubSub.notify_new_transaction(tx_address)
  end

  defp process_message({:cross_validate, tx_address, stamp = %ValidationStamp{}})
       when is_binary(tx_address) do
    Mining.cross_validate(tx_address, stamp)
  end

  defp process_message(
         {:set_replication_trees, tx_address, chain_storage_trees, beacon_storage_trees}
       )
       when is_binary(tx_address) and is_list(chain_storage_trees) and
              is_list(beacon_storage_trees) do
    Mining.set_replication_trees(tx_address, chain_storage_trees, beacon_storage_trees)
  end

  defp process_message(
         {:cross_validation_done, tx_address, {signature, inconsistencies, public_key}}
       )
       when is_binary(tx_address) and is_binary(signature) and is_list(inconsistencies) and
              is_binary(public_key) do
    Mining.add_cross_validation_stamp(tx_address, {signature, inconsistencies, public_key})
  end

  defp process_message({:get_beacon_slots, slots}) when is_list(slots) do
    slots
    |> Enum.map(fn {subset, dates} -> Beacon.previous_slots(subset, dates) end)
    |> Enum.flat_map(& &1)
  end

  defp process_message({:add_node_info, subset, node_info = %NodeInfo{}})
       when is_binary(subset) do
    Beacon.add_node_info(subset, node_info)
  end

  defp process_message({:get_last_transaction, last_address}) when is_binary(last_address) do
    UnirisCore.get_last_transaction(last_address)
  end

  defp do_process_messages([message | rest], acc) do
    result = process_message(message)
    do_process_messages(rest, [result | acc])
  end

  defp do_process_messages([], acc), do: Enum.reverse(acc)

  defp loop_node_info(node_public_key, date) do
    case P2P.node_info(node_public_key) do
      {:ok, _} ->
        {:ok, Crypto.encrypt_storage_nonce(node_public_key)}

      _ ->
        if DateTime.diff(date, DateTime.utc_now()) >= 3 do
          {:error, :unauthorized_node}
        else
          loop_node_info(node_public_key, date)
        end
    end
  end
end
