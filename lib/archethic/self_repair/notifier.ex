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

  alias Archethic.BeaconChain
  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.ShardRepair
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.Utils

  use GenServer, restart: :temporary
  @vsn 1

  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(args) do
    availability_update = Keyword.fetch!(args, :availability_update)

    seconds = DateTime.diff(availability_update, DateTime.utc_now())

    if seconds > 0 do
      Process.send_after(self(), :start, seconds * 1000)
    else
      send(self(), :start)
    end

    {:ok, args}
  end

  def handle_info(:start, data) do
    previous_nodes = Keyword.fetch!(data, :previous_nodes)
    new_nodes = Keyword.fetch!(data, :new_nodes)

    Logger.info("Start Notifier due to a topology change")

    repair_transactions(previous_nodes, new_nodes)
    repair_summaries_aggregate(previous_nodes, new_nodes)

    {:stop, :normal, data}
  end

  @doc """
  For each txn chain in db. Load its genesis address, load its
  chain, recompute shards , notifiy nodes. Network txns are excluded.
  """
  @spec repair_transactions(list(Node.t()), list(Node.t())) :: :ok
  def repair_transactions(previous_nodes, new_nodes) do
    # We fetch all the transactions existing and check if the disconnected nodes were in storage nodes
    TransactionChain.list_first_addresses()
    |> Stream.reject(&network_chain?(&1))
    |> Stream.chunk_every(20)
    |> Stream.each(&concurrent_txn_processing(&1, previous_nodes, new_nodes))
    |> Stream.run()
  end

  defp network_chain?(address) do
    case TransactionChain.get_transaction(address, [:type]) do
      {:ok, %Transaction{type: type}} -> Transaction.network_type?(type)
      _ -> false
    end
  end

  defp concurrent_txn_processing(addresses, previous_nodes, new_nodes) do
    Task.Supervisor.async_stream_nolink(
      Archethic.task_supervisors(),
      addresses,
      &sync_chain(&1, previous_nodes, new_nodes),
      ordered: false,
      on_timeout: :kill_task
    )
    |> Stream.run()
  end

  defp sync_chain(address, previous_nodes, new_nodes) do
    genesis_address = TransactionChain.get_genesis_address(address)

    address
    |> TransactionChain.get([
      :address,
      validation_stamp: [ledger_operations: [:transaction_movements]]
    ])
    |> Stream.map(&compute_elections(&1, previous_nodes, new_nodes, genesis_address))
    |> Stream.filter(&election_changed?(&1))
    |> Stream.filter(&notify?(&1))
    |> Stream.map(&filter_nodes_to_notify(&1))
    |> map_last_addresses_for_node()
    |> notify_nodes(genesis_address)
  end

  defp compute_elections(
         %Transaction{
           address: address,
           validation_stamp: %ValidationStamp{
             protocol_version: protocol_version,
             ledger_operations: %LedgerOperations{transaction_movements: transaction_movements},
             recipients: recipients
           }
         },
         previous_nodes,
         new_nodes,
         genesis_address
       ) do
    movements_addresses = transaction_movements |> Enum.map(& &1.to) |> Enum.concat(recipients)

    # Before AEIP-21, resolve movements included only last addresses,
    # then we have to resolve the genesis address for all the movements
    resolved_addresses = compute_resolved_addresses(movements_addresses, protocol_version)

    prev_storage_nodes =
      address |> Election.chain_storage_nodes(previous_nodes) |> Enum.map(& &1.first_public_key)

    prev_io_nodes =
      [genesis_address | resolved_addresses]
      |> Election.io_storage_nodes(previous_nodes)
      |> Enum.map(& &1.first_public_key)

    new_storage_nodes =
      Election.chain_storage_nodes(address, new_nodes) |> Enum.map(& &1.first_public_key)

    new_io_nodes =
      [genesis_address | resolved_addresses]
      |> Election.io_storage_nodes(new_nodes)
      |> Enum.map(& &1.first_public_key)

    %{
      address: address,
      prev_storage_nodes: prev_storage_nodes,
      prev_io_nodes: prev_io_nodes,
      new_storage_nodes: new_storage_nodes,
      new_io_nodes: new_io_nodes
    }
  end

  defp election_changed?(%{
         prev_storage_nodes: prev_storage_nodes,
         prev_io_nodes: prev_io_nodes,
         new_storage_nodes: new_storage_nodes,
         new_io_nodes: new_io_nodes
       }) do
    prev_storage_nodes != new_storage_nodes or prev_io_nodes != new_io_nodes
  end

  defp compute_resolved_addresses(movements_addresses, protocol_version)
       when protocol_version <= 7 do
    authorized_nodes = P2P.authorized_and_available_nodes()

    Task.async_stream(
      movements_addresses,
      fn address ->
        storage_nodes = Election.chain_storage_nodes(address, authorized_nodes)

        {:ok, resolved_genesis_address} =
          TransactionChain.fetch_genesis_address(address, storage_nodes)

        resolved_genesis_address
      end,
      on_timeout: :kill_task,
      max_concurrency: max(System.schedulers_online(), length(movements_addresses))
    )
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Stream.map(fn {:ok, address} -> address end)
    |> Enum.uniq()
  end

  defp compute_resolved_addresses(movements_addresses, _protocol_version), do: movements_addresses

  # Notify only if the current node is part of the previous storage / io nodes
  # to reduce number of messages
  defp notify?(%{prev_io_nodes: prev_io_nodes, prev_storage_nodes: prev_storage_nodes}) do
    Enum.member?(prev_storage_nodes ++ prev_io_nodes, Crypto.first_node_public_key())
  end

  @doc """
  New election is carried out on the set of all authorized omiting unavailable_node.
  The set of previous storage nodes is subtracted from the set of new storage nodes.
  """
  @spec filter_nodes_to_notify(map()) :: {binary(), list(Crypto.key()), list(Crypto.key())}
  def filter_nodes_to_notify(%{
        address: address,
        new_io_nodes: new_io_nodes,
        new_storage_nodes: new_storage_nodes,
        prev_io_nodes: prev_io_nodes,
        prev_storage_nodes: prev_storage_nodes
      }) do
    new_storage_nodes = new_storage_nodes -- prev_storage_nodes

    already_stored_nodes = Enum.uniq(prev_storage_nodes ++ prev_io_nodes ++ new_storage_nodes)

    new_io_nodes = new_io_nodes -- already_stored_nodes

    {address, new_storage_nodes, new_io_nodes}
  end

  @doc """
  Create a map returning for each node the last transaction address it should replicate
  """
  @spec map_last_addresses_for_node(Enumerable.t()) :: Enumerable.t()
  def map_last_addresses_for_node(stream) do
    Enum.reduce(
      stream,
      %{},
      fn {address, new_storage_nodes, new_io_nodes}, acc ->
        acc =
          Enum.reduce(new_storage_nodes, acc, fn first_public_key, acc ->
            Map.update(
              acc,
              first_public_key,
              %{last_address: address, io_addresses: []},
              &Map.put(&1, :last_address, address)
            )
          end)

        Enum.reduce(new_io_nodes, acc, fn first_public_key, acc ->
          Map.update(
            acc,
            first_public_key,
            %{last_address: nil, io_addresses: [address]},
            &Map.update(&1, :io_addresses, [address], fn addresses -> [address | addresses] end)
          )
        end)
      end
    )
  end

  defp notify_nodes(acc, genesis_address) do
    Task.Supervisor.async_stream_nolink(
      Archethic.task_supervisors(),
      acc,
      fn {node_first_public_key, %{last_address: last_address, io_addresses: io_addresses}} ->
        Logger.info(
          "Send Shard Repair message to #{Base.encode16(node_first_public_key)}" <>
            "with storage_address #{if last_address, do: Base.encode16(last_address), else: nil}, " <>
            "io_addresses #{inspect(Enum.map(io_addresses, &Base.encode16(&1)))}",
          address: Base.encode16(genesis_address)
        )

        P2P.send_message(node_first_public_key, %ShardRepair{
          genesis_address: genesis_address,
          storage_address: last_address,
          io_addresses: io_addresses
        })
      end,
      ordered: false,
      on_timeout: :kill_task
    )
    |> Stream.run()
  end

  @doc """
  For each beacon aggregate, calculate the new election and store it if the node needs to
  """
  @spec repair_summaries_aggregate(list(Node.t()), list(Node.t())) :: :ok
  def repair_summaries_aggregate(previous_nodes, new_nodes) do
    %Node{enrollment_date: first_enrollment_date} = P2P.get_first_enrolled_node()

    first_enrollment_date
    |> BeaconChain.next_summary_dates()
    |> Stream.filter(&download?(&1, new_nodes))
    |> Stream.chunk_every(20)
    |> Stream.each(fn summary_times ->
      Task.Supervisor.async_stream_nolink(
        Archethic.task_supervisors(),
        summary_times,
        &download_and_store_summary(&1, previous_nodes),
        ordered: false,
        on_timeout: :kill_task
      )
      |> Stream.run()
    end)
    |> Stream.run()
  end

  defp download?(summary_time, new_nodes) do
    in_new_election? =
      summary_time
      |> Crypto.derive_beacon_aggregate_address()
      |> Election.chain_storage_nodes(new_nodes)
      |> Utils.key_in_node_list?(Crypto.first_node_public_key())

    if in_new_election? do
      case BeaconChain.get_summaries_aggregate(summary_time) do
        {:ok, _} -> false
        {:error, _} -> true
      end
    else
      false
    end
  end

  defp download_and_store_summary(summary_time, previous_nodes) do
    storage_nodes =
      summary_time
      |> Crypto.derive_beacon_aggregate_address()
      |> Election.chain_storage_nodes(previous_nodes)

    case BeaconChain.fetch_summaries_aggregate(summary_time, storage_nodes) do
      {:ok, aggregate} ->
        Logger.debug("Notifier store beacon aggregate for #{summary_time}")
        BeaconChain.write_summaries_aggregate(aggregate)

      error ->
        Logger.warning(
          "Notifier cannot fetch summary aggregate for date #{summary_time} " <>
            "because of #{inspect(error)}"
        )
    end
  end
end
