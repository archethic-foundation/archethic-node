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
  """

  alias Archethic.{
    Crypto,
    Election,
    P2P,
    P2P.Message.ShardRepair,
    TransactionChain,
    TransactionChain.Transaction
  }

  require Logger
  use Task

  @spec start_link(args :: list(Crypto.key())) :: {:ok, pid()}
  def start_link(unavailable_nodes) do
    Task.start_link(__MODULE__, :run, [unavailable_nodes])
  end

  def run(unavailable_nodes) do
    repair_transactions(unavailable_nodes)
  end

  @doc """
  For each txn chain in db. Load its genesis address, load its
  chain, recompute shards , notifiy nodes. Network txns are excluded.
  """
  @spec repair_transactions(list(Crypto.key())) :: :ok
  def repair_transactions(unavailable_nodes) do
    Logger.debug(
      "Trying to repair transactions due to a topology change #{inspect(Enum.map(unavailable_nodes, &Base.encode16(&1)))}"
    )

    # We fetch all the transactions existing and check if the disconnected nodes were in storage nodes
    TransactionChain.stream_first_addresses()
    |> Stream.reject(&network_chain?(&1))
    |> Stream.chunk_every(20)
    |> Stream.each(fn chunk ->
      concurrent_txn_processing(chunk, unavailable_nodes)
    end)
    |> Stream.run()
  end

  defp network_chain?(address) do
    case TransactionChain.get_transaction(address, [:type]) do
      {:ok, %Transaction{type: type}} ->
        Transaction.network_type?(type)

      _ ->
        false
    end
  end

  defp concurrent_txn_processing(addresses, unavailable_nodes) do
    Task.Supervisor.async_stream_nolink(
      Archethic.TaskSupervisor,
      addresses,
      &sync_chain(&1, unavailable_nodes),
      ordered: false,
      on_timeout: :kill_task
    )
    |> Stream.run()
  end

  @doc """
  Loads a Txn Chain by it's first address, allocate new storage nodes for each transaction
  where the disconnected nodes were storage nodes
  """
  @spec sync_chain(binary(), list(Crypto.key())) :: :ok
  def sync_chain(address, unavailable_nodes) do
    address
    |> TransactionChain.stream([:address])
    |> Stream.map(&get_previous_election(&1))
    |> Stream.filter(&storage_node?(&1, unavailable_nodes))
    |> Stream.filter(&notify?(&1))
    |> Stream.map(&new_storage_nodes(&1, unavailable_nodes))
    |> map_last_address_for_node()
    |> notify_nodes(address)
  end

  defp get_previous_election(%Transaction{address: address}) do
    node_list = P2P.authorized_nodes()

    prev_storage_nodes =
      Election.chain_storage_nodes(address, node_list)
      |> Enum.map(& &1.first_public_key)

    {address, prev_storage_nodes}
  end

  defp storage_node?({_address, nodes}, unavailable_nodes) do
    Enum.any?(unavailable_nodes, &Enum.member?(nodes, &1))
  end

  defp notify?({_address, nodes}) do
    Enum.member?(nodes, Crypto.first_node_public_key())
  end

  @doc """
  New election is carried out on the set of all authorized omiting unavailable_node.
  The set of previous storage nodes is subtracted from the set of new storage nodes.
  """
  @spec new_storage_nodes({binary(), list(Crypto.key())}, list(Crypto.key())) ::
          {binary(), list(Crypto.key())}
  def new_storage_nodes({address, prev_storage_nodes}, unavailable_nodes) do
    new_authorized_nodes =
      P2P.authorized_nodes()
      |> Enum.reject(&Enum.member?(unavailable_nodes, &1.first_public_key))

    node_list =
      Election.chain_storage_nodes(address, new_authorized_nodes)
      |> Enum.map(& &1.first_public_key)
      |> Enum.reject(&Enum.member?(prev_storage_nodes, &1))

    {address, node_list}
  end

  @doc """
  Create a map returning for each node the last transaction address it should replicate
  """
  @spec map_last_address_for_node(Enumerable.t()) :: Enumerable.t()
  def map_last_address_for_node(stream) do
    Enum.reduce(stream, %{}, fn {address, nodes}, acc ->
      Enum.reduce(nodes, acc, fn first_public_key, acc ->
        Map.put(acc, first_public_key, address)
      end)
    end)
  end

  defp notify_nodes(acc, first_address) do
    Task.Supervisor.async_stream_nolink(
      Archethic.TaskSupervisor,
      acc,
      fn {node_key, address} ->
        P2P.send_message(node_key, %ShardRepair{
          first_address: first_address,
          last_address: address
        })
      end,
      ordered: false,
      on_timeout: :kill_task
    )
    |> Stream.run()
  end
end
