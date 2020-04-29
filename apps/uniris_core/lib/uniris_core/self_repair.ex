defmodule UnirisCore.SelfRepair do
  use GenServer

  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node
  alias UnirisCore.Beacon
  alias UnirisCore.BeaconSlot
  alias UnirisCore.BeaconSlot.TransactionInfo
  alias UnirisCore.BeaconSlot.NodeInfo
  alias UnirisCore.Election
  alias UnirisCore.Storage
  alias UnirisCore.Crypto
  alias UnirisCore.Transaction
  alias UnirisCore.Utils

  @last_sync_dir Application.app_dir(:uniris_core, "priv/last_sync")

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_sync(node_patch, fire_sync \\ true)
      when is_binary(node_patch) and is_boolean(fire_sync) do
    GenServer.call(__MODULE__, {:start_sync, node_patch, fire_sync})
  end

  def last_sync_date() do
    file = last_sync_file()

    if File.exists?(file) do
      file
      |> File.read!()
      |> String.to_integer()
      |> DateTime.from_unix!()
    else
      Application.get_env(:uniris_core, UnirisCore.SelfRepair)[:network_startup_date]
    end
  end

  def init(opts) do
    File.mkdir_p(@last_sync_dir)

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
        |> update_last_sync_date()
        |> Map.put(:node_patch, node_patch)

      {:reply, :ok, new_state}
    end
  end

  def handle_continue(
        {:first_sync, from_pid},
        state = %{node_patch: node_patch, last_sync_date: last_sync_date, interval: interval}
      ) do
    synchronize(last_sync_date, node_patch)
    send(from_pid, :sync_finished)
    schedule_sync(Utils.time_offset(interval))
    {:noreply, update_last_sync_date(state)}
  end

  def handle_info(
        :sync,
        state = %{
          interval: interval,
          last_sync_date: last_sync_date,
          node_patch: node_patch
        }
      ) do
    Logger.info("Self-repair synchronization started")
    synchronize(last_sync_date, node_patch)
    schedule_sync(interval)
    {:noreply, update_last_sync_date(state)}
  end

  defp update_last_sync_date(state) do
    next_sync_date = DateTime.utc_now()
    store_last_sync_date(next_sync_date)
    Map.put(state, :last_sync_date, next_sync_date)
  end

  defp schedule_sync(0), do: :ok

  defp schedule_sync(interval) do
    Process.send_after(self(), :sync, interval)
  end

  # Retreive missing transactions from the missing beacon chain slots
  # Beacon chain pools are retrieved from the given latest synchronization date including all the beacon subsets (i.e <<0>>, <<1>>, etc.)
  # Once retrieved, the transactions are downloaded and stored if not exists locally
  defp synchronize(last_sync_date, node_patch) do
    Beacon.get_pools(last_sync_date)
    |> slots_to_sync(last_sync_date, node_patch)
    |> synchronize_missing_slots(node_patch)
  end

  defp store_last_sync_date(date) do
    data = DateTime.to_unix(date) |> Integer.to_string()
    File.write!(last_sync_file(), data, [:write])
  end

  # Request beacon pools the slot informations before a last synchronization time
  defp slots_to_sync([], _, _), do: []

  defp slots_to_sync(pools, last_sync_date, node_patch) do
    Task.async_stream(pools, &query_beacon_slot_data(&1, last_sync_date, node_patch))
    |> Enum.into([], fn {:ok, res} -> res end)
    |> Enum.flat_map(& &1)
  end

  defp query_beacon_slot_data({_, []}, _, _), do: []

  defp query_beacon_slot_data({subset, nodes}, last_sync_date, node_patch) do
    nodes
    |> P2P.nearest_nodes(node_patch)
    |> List.first()
    |> P2P.send_message({:get_beacon_slots, subset, DateTime.to_unix(last_sync_date)})
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
    transaction_infos
    |> Enum.reject(&transaction_exists?(&1.address))
    # Prioritize node transactions
    # TODO: same with other network type transactions
    |> Enum.sort_by(& &1.timestamp, :desc)
    |> Enum.sort_by(fn %TransactionInfo{type: type} -> type end, fn type, _ -> type == :node end)
    |> Enum.each(&handle_transaction_info(&1, node_patch))
  end

  defp handle_transaction_info(%TransactionInfo{address: address, type: type}, node_patch) do
    storage_nodes =
      if Transaction.network_type?(type) do
        P2P.list_nodes()
      else
        Election.storage_nodes(address)
      end
      |> P2P.nearest_nodes(node_patch)
      |> Enum.map(& &1.first_public_key)

    if Crypto.node_public_key(0) in storage_nodes do
      if Transaction.network_type?(type) do
        tx = download_transaction(storage_nodes, address)
        Storage.write_transaction(tx)
      else
        # TODO: build the transaction history to create a tree to fetch the latest transaction chain
        chain = download_transaction_chain(storage_nodes, address)
        Storage.write_transaction_chain(chain)
      end
    end
  end

  defp update_node_infos(node_infos) do
    Enum.each(node_infos, fn %NodeInfo{public_key: public_key, ready?: ready?} ->
      if ready? do
        Node.set_ready(public_key)
      end
    end)
  end

  defp download_transaction(nodes, address) do
    do_download(nodes, {:get_transaction, address})
  end

  defp download_transaction_chain(nodes, address) do
    do_download(nodes, {:get_transaction_chain, address})
  end

  defp do_download([node | rest], message) do
    case P2P.send_message(node, message) do
      {:ok, result} ->
        result

      _ ->
        do_download(rest, message)
    end
  end

  defp do_download([], _), do: {:error, :network_issue}

  defp transaction_exists?(address) do
    case Storage.get_transaction(address) do
      {:ok, _} ->
        true

      _ ->
        false
    end
  end

  defp last_sync_file() do
    Path.join(@last_sync_dir, Base.encode16(Crypto.node_public_key(0)))
  end
end
