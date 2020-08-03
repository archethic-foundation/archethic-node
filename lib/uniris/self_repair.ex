defmodule Uniris.SelfRepair do
  @moduledoc """
  Process responsible of the self repair mechanism by pulling for each interval
  the last unsynchronized beacon chain slots.

  It downloads the missing transactions and node updates
  """
  use GenServer

  alias Uniris.Beacon
  alias Uniris.BeaconSlot
  alias Uniris.BeaconSlot.NodeInfo
  alias Uniris.BeaconSlot.TransactionInfo

  alias Uniris.Crypto
  alias Uniris.Election
  alias Uniris.Mining.Replication

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetBeaconSlots
  alias Uniris.P2P.Message.GetTransaction
  alias Uniris.P2P.Node

  alias Uniris.Storage
  alias Uniris.TaskSupervisor
  alias Uniris.Transaction

  alias Uniris.Utils

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_sync(node_patch, fire_sync \\ true)
      when is_binary(node_patch) and is_boolean(fire_sync) do
    GenServer.call(__MODULE__, {:start_sync, node_patch, fire_sync})
  end

  def last_sync_date do
    file = last_sync_file()

    if File.exists?(file) do
      file
      |> File.read!()
      |> String.to_integer()
      |> DateTime.from_unix!()
      |> Utils.truncate_datetime()
    else
      Application.get_env(:uniris, Uniris.SelfRepair)[:network_startup_date]
    end
  end

  def init(opts) do
    interval = Keyword.get(opts, :interval)

    {:ok,
     %{
       interval: interval,
       last_sync_date: last_sync_date()
     }}
  end

  def handle_call(
        {:start_sync, node_patch, fire_sync?},
        {from_pid, _ref},
        state = %{interval: interval}
      ) do
    if fire_sync? do
      {:reply, :ok, Map.put(state, :node_patch, node_patch), {:continue, {:first_sync, from_pid}}}
    else
      schedule_sync(Utils.time_offset(interval))

      new_state =
        state
        |> Map.put(:node_patch, node_patch)
        |> Map.put(:last_sync_date, update_last_sync_date())

      {:reply, :ok, new_state}
    end
  end

  def handle_continue(
        {:first_sync, from_pid},
        state = %{
          node_patch: node_patch,
          last_sync_date: last_sync_date,
          interval: interval
        }
      ) do
    synchronize(last_sync_date, node_patch)
    send(from_pid, :sync_finished)
    schedule_sync(Utils.time_offset(interval))
    {:noreply, Map.put(state, :last_sync_date, update_last_sync_date())}
  end

  def handle_info(
        :sync,
        state = %{
          interval: interval,
          last_sync_date: last_sync_date,
          node_patch: node_patch
        }
      ) do
    Logger.info("Self-repair synchronization started from #{inspect(last_sync_date)}")
    synchronize(last_sync_date, node_patch)
    schedule_sync(interval)
    {:noreply, Map.put(state, :last_sync_date, update_last_sync_date())}
  end

  defp update_last_sync_date do
    next_sync_date = Utils.truncate_datetime(DateTime.utc_now())
    store_last_sync_date(next_sync_date)
    next_sync_date
  end

  defp schedule_sync(0), do: :ok

  defp schedule_sync(interval) do
    Process.send_after(self(), :sync, interval)
  end

  # Retreive missing transactions from the missing beacon chain slots
  # Beacon chain pools are retrieved from the given latest synchronization
  # date including all the beacon subsets (i.e <<0>>, <<1>>, etc.)
  # Once retrieved, the transactions are downloaded and stored if not exists locally
  defp synchronize(last_sync_date, node_patch) do
    Beacon.get_pools(last_sync_date)
    |> batch_slots(node_patch)
    |> get_beacon_slots()
    |> synchronize_missing_slots(node_patch)
  end

  defp store_last_sync_date(date) do
    data = DateTime.to_unix(date) |> Integer.to_string()
    filename = last_sync_file()
    File.mkdir_p!(Path.dirname(filename))
    File.write!(filename, data, [:write])
  end

  # Batch and group the slot by nodes and date before the last synchronization time
  defp batch_slots([], _) do
    []
  end

  defp batch_slots(pools, node_patch) do
    pools
    |> group_pools_by_subset_and_date()
    |> group_subset_by_closest_nodes(node_patch)
  end

  # Request beacon pools the slot informations before the last synchronization time
  defp get_beacon_slots(slot_batches) do
    TaskSupervisor
    |> Task.Supervisor.async_stream_nolink(slot_batches, fn {node, subset_map} ->
      P2P.send_message(node, %GetBeaconSlots{subsets_slots: subset_map})
    end)
    |> Enum.into([], fn {:ok, res} -> res end)
    |> Enum.flat_map(& &1.slots)
    |> Enum.uniq()
  end

  # Group the nodes by date of sync and by subset
  #
  # Examples
  #
  # { "01", [ { "01/01/2020", [ "nodeA", "nodeB"] }, { "01/02/2020", ["nodeB", "nodeC"] } ] }
  # => %{
  #  "01" => %{
  #    "01/01/2020" => ["nodeA", "nodeB"],
  #    "02/01/2020" => ["nodeB", "nodeC"]
  #  }
  # }
  defp group_pools_by_subset_and_date(pools, acc \\ %{})

  defp group_pools_by_subset_and_date([{subset, nodes_by_slots} | rest], acc) do
    acc = reduce_subsets_and_date(subset, nodes_by_slots, acc)
    group_pools_by_subset_and_date(rest, acc)
  end

  defp group_pools_by_subset_and_date([], acc), do: acc

  defp reduce_subsets_and_date(subset, [{date, nodes} | rest], acc) do
    acc =
      Map.update(acc, subset, %{date => nodes}, fn prev ->
        Map.update(prev, date, nodes, &Enum.uniq(&1 ++ nodes))
      end)

    reduce_subsets_and_date(subset, rest, acc)
  end

  defp reduce_subsets_and_date(_subset, [], acc), do: acc

  # Group closest nodes
  #
  # Examples
  #
  # %{
  #   "01" => %{
  #      "01/01/2020" => ["nodeA", "nodeB"],
  #      "02/01/2020" => ["nodeB", "nodeC"]
  #   }
  # }
  # => %{
  #   "nodeA" => %{
  #      "01" => ["01/01/2020"]
  #    },
  #    "nodeB" => {
  #      "01" => ["01/01/2020", "02/01/2020"]
  #    }
  # }
  defp group_subset_by_closest_nodes(subsets, node_patch) do
    Enum.reduce(subsets, %{}, fn {subset, nodes_by_date}, acc ->
      nodes_by_date
      |> Enum.map(&map_nearest_nodes_per_date(node_patch, &1))
      |> Enum.reduce(acc, &reduce_synchronization_slots_per_subsets(subset, &1, &2))
    end)
  end

  defp map_nearest_nodes_per_date(node_patch, {date, nodes}) do
    {
      date,
      nodes
      |> P2P.nearest_nodes(node_patch)
      |> Enum.take(5)
    }
  end

  defp reduce_synchronization_slots_per_subsets(subset, {date, nodes}, acc) do
    Enum.reduce(nodes, acc, fn node, acc ->
      Map.update(acc, node, %{subset => [date]}, fn prev ->
        Map.update(prev, subset, [date], &Enum.uniq([date | &1]))
      end)
    end)
  end

  defp synchronize_missing_slots(slots, node_patch) do
    %BeaconSlot{transactions: transactions, nodes: nodes} = reduce_slots(slots)
    synchronize_transactions(transactions, node_patch)
    update_node_infos(nodes)
  end

  defp reduce_slots(slots) do
    Enum.reduce(slots, %BeaconSlot{}, fn %BeaconSlot{transactions: transactions, nodes: nodes},
                                         acc ->
      acc = Enum.reduce(nodes, acc, &BeaconSlot.add_node_info(&2, &1))
      Enum.reduce(transactions, acc, &BeaconSlot.add_transaction_info(&2, &1))
    end)
  end

  defp synchronize_transactions(transaction_infos, node_patch) do
    transaction_infos =
      transaction_infos
      |> Enum.reject(&transaction_exists?(&1.address))
      # Need to download the latest transactions and the the newest
      # to ensure transaction chain integrity verification
      |> Enum.sort_by(& &1.timestamp, :asc)
      |> Enum.sort_by(& &1.type, fn type, _ -> Transaction.network_type?(type) end)
      |> Enum.sort_by(& &1.type, fn type_a, type_b ->
        # TODO: same with other network type transactions
        cond do
          type_a == :node and type_b == :node_shared_secrets ->
            true

          type_a == :node_shared_secrets and type_b == :node ->
            false

          true ->
            true
        end
      end)

    Enum.each(transaction_infos, &download_transaction(&1, node_patch))
  end

  defp transaction_storage_nodes(%TransactionInfo{address: address, type: type}) do
    if Transaction.network_type?(type) do
      P2P.list_nodes()
    else
      Election.storage_nodes(address, P2P.list_nodes())
    end
  end

  defp download_transaction(
         tx_info = %TransactionInfo{address: address, movements_addresses: movements_addresses},
         node_patch
       ) do
    if !transaction_exists?(address) do
      process_missed_transaction(tx_info, node_patch)
    end

    # Process the movements address and determines if your are member of
    # the IO storage pool for transaction and node movements
    movements_addresses
    |> Enum.reject(&transaction_exists?/1)
    |> Enum.each(&process_movement_address(&1, node_patch))
  end

  defp process_missed_transaction(
         tx_info = %TransactionInfo{address: address, type: type},
         node_patch
       ) do
    storage_nodes = transaction_storage_nodes(tx_info)
    # Only elected storage nodes must download the transactions
    if Crypto.node_public_key(0) in Enum.map(storage_nodes, & &1.first_public_key) do
      Logger.info("Download transaction #{type}@#{Base.encode16(address)}")
      do_download(address, storage_nodes, node_patch)
    end
  end

  defp process_movement_address(address, node_patch) do
    storage_nodes = Election.storage_nodes(address, P2P.list_nodes())

    if Crypto.node_public_key(0) in Enum.map(storage_nodes, & &1.first_public_key) do
      Logger.info("Download transaction movement #{Base.encode16(address)}")
      do_download(address, storage_nodes, node_patch)
    end
  end

  defp do_download(address, storage_nodes, node_patch) do
    downloading_nodes =
      storage_nodes
      |> Enum.filter(& &1.ready?)
      |> Enum.reject(&(&1.first_public_key == Crypto.node_public_key(0)))
      |> P2P.nearest_nodes(node_patch)

    tx =
      %Transaction{previous_public_key: previous_public_key} =
      request_nodes(downloading_nodes, %GetTransaction{address: address})

    previous_chain = Storage.get_transaction_chain(Crypto.hash(previous_public_key))
    next_chain = [tx | previous_chain]

    Logger.debug(
      "New transaction chain to store: #{
        inspect(Enum.map(next_chain, &Base.encode16(&1.address)))
      }"
    )

    with true <- Replication.valid_transaction?(tx),
         true <- Replication.valid_chain?(next_chain) do
      Storage.write_transaction_chain(next_chain)
    else
      _ ->
        Logger.error("Invalid transaction chain #{Base.encode16(tx.address)}")
    end
  end

  defp update_node_infos(node_infos) do
    Enum.each(node_infos, fn %NodeInfo{
                               public_key: public_key,
                               ready?: ready?,
                               timestamp: timestamp
                             } ->
      if ready? do
        Node.set_ready(public_key, timestamp)
      end
    end)
  end

  defp request_nodes([node | rest], message) do
    case P2P.send_message(node, message) do
      tx = %Transaction{} ->
        tx

      _ ->
        request_nodes(rest, message)
    end
  end

  defp request_nodes([], _), do: {:error, :network_issue}

  defp transaction_exists?(address) do
    case Storage.get_transaction(address) do
      {:ok, _} ->
        true

      _ ->
        false
    end
  end

  defp last_sync_file do
    relative_filepath =
      :uniris
      |> Application.get_env(__MODULE__)
      |> Keyword.get(:last_sync_file, "priv/p2p/last_sync")

    Application.app_dir(:uniris, relative_filepath)
  end
end
