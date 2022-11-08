defmodule Archethic.SelfRepair.Notifier do
  @moduledoc """
  Process to handle repair in case of topology change by trying to replicate transactions to new shard composition.

  When a node receive a topology change due to the unavailability of a node,
  we compute the new election for the already stored transactions.

  Hence, a new shard might me formed as we notify the new transactions to the
  new storage nodes

  ```mermaid
  flowchart TD
      A[Node 4] --x|Topology change notification| B[Node1]
      B --> | List transactions| B
      B -->|Elect new nodes| H[Transaction replication]
      H -->|Replicate Transaction| C[Node2]
      H -->|Replicate Transaction| D[Node3]
  ```

   Different nodes holding same chain, but with different length of txn chain
   node       | node-A| node-B| node-C| node-D    | node-E
   txn_chain  | 1     | 1 2   | 1 2 3 | 1 2 3 4 5| 1 2 3 4 5

   Sharding on single txn results in holding that txn chain upto that txn
   txn_chain => A -> B -> C -> D
   A Sharded tranction replication mean tx from genesis addr to that tx address.
  """
  use GenServer
  require Logger

  alias Archethic.{
    Crypto,
    Election,
    PubSub,
    P2P,
    P2P.Node,
    P2P.Message.ShardRepair,
    TransactionChain,
    TransactionChain.Transaction
  }

  @network_type_transactions Transaction.list_network_type()

  @spec start_link(args :: list() | []) :: GenServer.on_start()
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_) do
    PubSub.register_to_node_update()
    {:ok, %{notified: %{}}}
  end

  def handle_info(
        {:node_update,
         %Node{
           available?: false,
           authorized?: true,
           first_public_key: node_key,
           authorization_date: authorization_date
         }},
        state = %{notified: notified}
      ) do
    current_node_public_key = Crypto.first_node_public_key()
    now = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    with :lt <- DateTime.compare(authorization_date, now),
         nil <- Map.get(notified, node_key),
         false <- current_node_public_key == node_key do
      repair_transactions(node_key, current_node_public_key)
      {:noreply, Map.update!(state, :notified, &Map.put(&1, node_key, %{}))}
    else
      _ ->
        {:noreply, state}
    end
  end

  def handle_info(
        {:node_update,
         %Node{authorized?: false, authorization_date: date, first_public_key: node_key}},
        state = %{notified: notified}
      )
      when date != nil do
    current_node_public_key = Crypto.first_node_public_key()

    with nil <- Map.get(notified, node_key),
         false <- current_node_public_key == node_key do
      repair_transactions(node_key, current_node_public_key)
      {:noreply, Map.update!(state, :notified, &Map.put(&1, node_key, %{}))}
    else
      _ ->
        {:noreply, state}
    end
  end

  def handle_info(
        {:node_update,
         %Node{available?: true, first_public_key: node_key, authorization_date: date}},
        state
      )
      when date != nil do
    {:noreply, Map.update!(state, :notified, &Map.delete(&1, node_key))}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  @doc """
  Determines whether a genesis address belongs to a network chain.
  """
  @spec network_chain?(binary()) :: boolean()
  def network_chain?(genesis_address) do
    case TransactionChain.get_transaction(genesis_address, [:type]) do
      {:ok, %Transaction{type: type}} when type in @network_type_transactions ->
        true

      _ ->
        false
    end
  end

  @doc """
  For each txn chain in db. Load its genesis address, load its
  chain, recompute shards , notifiy nodes. Network txns are excluded,
  dependent bootstrap operations.
  """
  @spec repair_transactions(Crypto.key(), Crypto.key()) :: :ok
  def repair_transactions(unavailable_node_key, current_node_public_key) do
    Logger.debug("Trying to repair transactions due to a topology change",
      node: Base.encode16(unavailable_node_key)
    )

    # We fetch all the transactions existing and check if the disconnecting node was a storage node

    TransactionChain.stream_genesis_addresses()
    |> Stream.filter(&(network_chain?(&1) == false))
    |> tap(fn x -> IO.inspect(x) end)
    |> Stream.each(&sync_chain_by_chain(&1, unavailable_node_key, current_node_public_key))
    |> Stream.run()
    |> tap(fn x -> IO.inspect(x) end)

    :ok
  end

  @doc """
  Loads a Txn Chain by a genesis address, Allocate new shards for the txn went down with down node.
  """
  @spec sync_chain_by_chain(binary(), Crypto.key(), Crypto.key()) :: :ok
  def sync_chain_by_chain(
        genesis_address,
        unavailable_node_key,
        current_node_public_key
      ) do
    genesis_address
    |> TransactionChain.stream([:address, validation_stamp: [:timestamp]])
    |> Stream.map(&list_previous_shards(&1))
    |> Stream.filter(&with_down_shard?(&1, unavailable_node_key))
    |> Stream.filter(&current_node_in_node_list?(&1, current_node_public_key))
    |> Stream.map(&new_storage_nodes(&1, unavailable_node_key))
    |> Stream.scan(%{}, &map_node_and_address(&1, _acc = &2))
    |> Stream.take(-1)
    |> Enum.take(1)
    |> notify_nodes(genesis_address)
  end

  @doc """
  Repair txns that was stored by currenltyy unavailable nodes
  For re-election and repair.
  """
  @spec list_previous_shards(Transaction.t()) :: {binary(), list(Crypto.key())}
  def list_previous_shards(txn) do
    node_list = get_nodes_list(txn.validation_stamp.timestamp)

    prev_storage_nodes =
      Election.chain_storage_nodes(txn.address, node_list)
      |> Enum.map(& &1.first_public_key)

    {txn.address, prev_storage_nodes}
  end

  @doc """
  Returns a node list that have been authorized before a given DateTime
  """
  @spec get_nodes_list(DateTime.t()) :: list(Crypto.key())
  def get_nodes_list(timestamp) do
    P2P.stream_nodes()
    |> Stream.filter(fn
      %P2P.Node{authorization_date: auth_date} when not is_nil(auth_date) ->
        DateTime.compare(auth_date, timestamp) == :lt

      _ ->
        false
    end)
    |> Enum.to_list()
  end

  @doc """
  Does the currently unavailable_node_key is in previously elected shards
  """
  @spec with_down_shard?({binary(), list(Crypto.key())}, Crypto.key()) :: boolean()
  def with_down_shard?({_address, node_list}, unavailable_node_key) do
    Enum.any?(node_list, &(&1 == unavailable_node_key))
  end

  @doc """
  Is current node key in the list of previous nodes/shards
  """
  @spec current_node_in_node_list?({binary(), list(Crypto.key())}, Crypto.key()) :: boolean()
  def current_node_in_node_list?({_address, node_list}, current_node_key) do
    Enum.any?(node_list, &(&1 == current_node_key))
  end

  @doc """
  New election is carried out on the set of all authorized omiting unavailable_node.
  The set of previous storage nodes is subtracted from the set of new storage nodes.
  """
  @spec new_storage_nodes({binary(), list(Crypto.key())}, Crypto.key()) ::
          {binary(), list(Crypto.key())}
  def new_storage_nodes({address, prev_storage_node}, unavailable_node_key) do
    node_list =
      Election.chain_storage_nodes(
        address,
        P2P.authorized_nodes()
        |> Enum.reject(&(&1.first_public_key == unavailable_node_key))
      )
      |> Enum.reject(&(&1.first_public_key in prev_storage_node))
      |> Enum.map(& &1.first_public_key)

    {address, node_list}
  end

  @doc """
  Acc in map, node key to the last address it should hold for a transaction chain.
  """
  @spec map_node_and_address({binary(), list(Crypto.key())}, map()) :: map()
  def map_node_and_address({address, node_list}, acc) do
    Enum.reduce(node_list, acc, fn first_public_key, acc ->
      Map.put(acc, first_public_key, address)
    end)
  end

  @doc """
  Deploys the ShardRepair message to the intended nodes.
  """
  @spec notify_nodes([map()], binary()) :: :ok
  def notify_nodes([], _), do: :ok

  def notify_nodes([acc], genesis_address) do
    Task.Supervisor.async_stream_nolink(
      Archethic.TaskSupervisor,
      acc,
      fn
        {node_key, address} ->
          P2P.send_message(node_key, %ShardRepair{
            genesis_address: genesis_address,
            last_address: address
          })
      end,
      ordered: false,
      on_timeout: :kill_task
    )
    |> Stream.run()
  end
end

#  genesis_address
#     |> TransactionChain.stream([:address, validation_stamp: [:timestamp]])
#     |> tap(fn x ->
#       Enum.each(x, &IO.inspect({&1.address, &1.validation_stamp.timestamp}, label: "1"))
#     end)
#     # |> tap(fn x -> IO.inspect(x, label: "----") end)
#     |> Stream.map(&list_previous_shards(&1))
#     |> Enum.to_list()
#     |> tap(fn x ->
#       IO.inspect(label: "2=======")

#       Enum.each(
#         x,
#         &IO.inspect({elem(&1, 0), length(elem(&1, 1))}, label: "post_list_shards==2==")
#       )
#     end)
#     |> Stream.filter(&with_down_shard?(&1, unavailable_node_key))
#     |> Enum.to_list()
#     |> tap(fn x ->
#       IO.inspect(label: "3=======")
#       Enum.each(x, &IO.inspect({elem(&1, 0), length(elem(&1, 1))}, label: "with_down_shard==3=="))
#     end)
#     |> Stream.filter(&current_node_in_node_list?(&1, current_node_public_key))
#     |> Enum.to_list()
#     |> tap(fn x ->
#       IO.inspect(label: "4==")

#       Enum.each(
#         x,
#         &IO.inspect({elem(&1, 0), length(elem(&1, 1))}, label: " current_node_in_node_list4==")
#       )
#     end)
#     |> Stream.map(&new_storage_nodes(&1, unavailable_node_key))
#     |> Enum.to_list()
#     |> tap(fn x ->
#       IO.inspect(label: "5=======")

#       Enum.each(
#         x,
#         &IO.inspect({elem(&1, 0), length(elem(&1, 1))}, label: "5 new_storage_nodes==")
#       )
#     end)
#     |> Stream.scan(%{}, &map_node_and_address(&1, _acc = &2))
#     |> Enum.to_list()
#     |> tap(fn x -> IO.inspect(x, label: "6==") end)
#     |> Stream.take(-1)
#     |> Enum.to_list()
#     |> tap(fn x -> IO.inspect(x, label: "7==") end)
#     |> notify_nodes(genesis_address)
#     |> tap(fn x -> IO.inspect(x, label: "8==") end)

#     :ok
#   end
