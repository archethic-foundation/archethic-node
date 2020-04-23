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

  @last_sync_dir Application.app_dir(:uniris_core, "priv/last_sync")

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    File.mkdir_p(@last_sync_dir)

    repair_interval = Keyword.get(opts, :repair_interval)

    {:ok,
     %{
       repair_interval: repair_interval,
       last_sync_date: last_sync_date(),
       node_patch: nil
     }}
  end

  def handle_cast({:start_sync, node_patch}, state = %{repair_interval: interval}) do
    current_time = Time.utc_now().second * 1000
    last_interval = interval * trunc(current_time / interval)
    next_interval = last_interval + interval
    offset = next_interval - current_time
    schedule_sync(offset)

    {:noreply, Map.put(state, :node_patch, node_patch)}
  end

  def handle_info(:sync, state = %{node_patch: nil, repair_interval: interval}) do
    schedule_sync(interval)
    {:noreply, state}
  end

  def handle_info(
        :sync,
        state = %{
          repair_interval: interval,
          last_sync_date: last_sync_date,
          node_patch: node_patch
        }
      ) do
    Logger.info("Self-repair synchronization started")
    synchronize(last_sync_date, node_patch)
    schedule_sync(interval)
    next_sync_date = DateTime.utc_now()
    store_last_sync_date(next_sync_date)

    {:noreply, Map.put(state, :last_sync_date, next_sync_date)}
  end

  defp schedule_sync(0), do: :ok

  defp schedule_sync(interval) do
    Process.send_after(self(), :sync, interval)
  end

  @doc """
  Proceed to the synchronization of the missing informations from the beacon chains
  """
  def synchronize(last_sync_date = %DateTime{}, node_patch) when is_binary(node_patch) do
    Beacon.get_pools(last_sync_date)
    |> slots_to_sync(last_sync_date, node_patch)
    |> synchronize_missing_slots(node_patch)
  end

  defp store_last_sync_date(date) do
    data = DateTime.to_unix(date) |> Integer.to_string()
    File.write!(last_sync_file(), data, [:write])
  end

  @doc """
  Request beacon pools the slot informations before a last synchronization time
  """
  def slots_to_sync([], _, _), do: []

  def slots_to_sync(pools, last_sync_date, node_patch) do
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
    %BeaconSlot{transactions: transactions, nodes: nodes} =
      Enum.reduce(slots, %BeaconSlot{}, fn %BeaconSlot{transactions: transactions, nodes: nodes},
                                           acc ->
        acc = Enum.reduce(nodes, acc, &BeaconSlot.add_node_info(&2, &1))
        Enum.reduce(transactions, acc, &BeaconSlot.add_transaction_info(&2, &1))
      end)

    synchronize_transactions(transactions, node_patch)
    update_node_infos(nodes)
  end

  defp synchronize_transactions(transaction_infos, node_patch) do
    transaction_infos
    |> Enum.reject(fn %TransactionInfo{address: address} -> transaction_exists?(address) end)
    # Prioritize node transactions
    # TODO: same with other network type transactions
    |> Enum.sort_by(fn %TransactionInfo{type: type} -> type end, fn type, _ -> type == :node end)
    |> Enum.each(fn %TransactionInfo{address: address, type: type} ->
      storage_nodes =
        if Transaction.network_type?(type) do
          P2P.list_nodes()
        else
          Election.storage_nodes(address)
        end
        |> P2P.nearest_nodes(node_patch)
        |> Enum.map(& &1.first_public_key)

      if Crypto.node_public_key(0) in storage_nodes do
        case type do
          :node_shared_secrets ->
            Crypto.increment_number_of_generate_node_shared_keys()
            IO.inspect "#{Crypto.number_of_node_shared_secrets_keys()}"
            tx = download_transaction(storage_nodes, address)
            Storage.write_transaction(tx, false)
          :node ->
            tx = download_transaction(storage_nodes, address)
            Storage.write_transaction(tx)
          _ ->
            # TODO: build the transaction history to create a tree to fetch the latest transaction chain
            chain = download_transaction_chain(storage_nodes, address)
            Storage.write_transaction_chain(chain)
        end
      end
    end)
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

  def start_sync(node_patch) when is_binary(node_patch) do
    GenServer.cast(__MODULE__, {:start_sync, node_patch})
  end

  defp transaction_exists?(address) do
    case Storage.get_transaction(address) do
      {:ok, _} ->
        true

      _ ->
        false
    end
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

  defp last_sync_file() do
    Path.join(@last_sync_dir, Base.encode16(Crypto.node_public_key(0)))
  end
end
