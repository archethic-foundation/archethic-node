defmodule ArchEthic.SelfRepair.Sync.BeaconSummaryHandler do
  @moduledoc false

  alias ArchEthic.BeaconChain
  alias ArchEthic.BeaconChain.Slot.EndOfNodeSync
  alias ArchEthic.BeaconChain.Summary, as: BeaconSummary

  alias ArchEthic.Crypto

  alias ArchEthic.DB

  alias ArchEthic.Election

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.BeaconSummaryList
  alias ArchEthic.P2P.Message.GetBeaconSummary
  alias ArchEthic.P2P.Message.GetBeaconSummaries
  alias ArchEthic.P2P.Message.GetTransaction
  alias ArchEthic.P2P.Message.NotFound
  alias ArchEthic.P2P.Node

  alias ArchEthic.PubSub

  alias __MODULE__.TransactionHandler

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction

  alias ArchEthic.Utils

  require Logger

  @doc """
  Retrieve the list of missed beacon summaries from a given date.

  Foreach summary time and subset, a list node of nodes will be requested
  to find out the missing beacon summaries.

  The downloads are performed in batch to avoid overload of messages between nodes.
  And a track of downloaded beacon summaries is kept to avoid failures and misses.

  Also if the current node is responsible to store the beacon summary, then it will fetch the transaction and store it.
  """
  @spec get_beacon_summaries(Enumerable.t(), binary()) :: Enumerable.t()
  def get_beacon_summaries(summary_pools, patch) when is_binary(patch) do
    summary_pools
    |> Enum.reduce(%{}, &reduce_beacon_address_by_node/2)
    |> Stream.transform([], &get_beacon_summaries_by_node/2)
    |> Stream.map(fn summary ->
      load_downloaded_summary(summary)
      summary
    end)
  end

  defp reduce_beacon_address_by_node({summary_time, subset, nodes}, acc) do
    beacon_address = Crypto.derive_beacon_chain_address(subset, summary_time, true)

    Enum.reduce(nodes, acc, fn node, acc ->
      Map.update(acc, node, [beacon_address], &[beacon_address | &1])
    end)
  end

  defp get_beacon_summaries_by_node({_, []}, acc), do: acc

  defp get_beacon_summaries_by_node(
         {node, addresses},
         resolved_addresses
       ) do
    %{summaries: summaries, resolved_addresses: new_resolved_addresses} =
      addresses
      |> Enum.reject(&(&1 in resolved_addresses))
      |> do_get_beacon_summaries_by_node(node)
      |> Enum.reduce(%{summaries: [], resolved_addresses: resolved_addresses}, fn summary, acc ->
        summary_address = get_address_from_summary(summary)

        acc
        |> Map.update!(:summaries, &[summary | &1])
        |> Map.update!(:resolved_addresses, &[summary_address | &1])
      end)

    {summaries, new_resolved_addresses}
  end

  defp do_get_beacon_summaries_by_node([], _node), do: []

  defp do_get_beacon_summaries_by_node(addresses, node) do
    case P2P.send_message(node, %GetBeaconSummaries{addresses: addresses}) do
      {:ok, %BeaconSummaryList{summaries: summaries}} ->
        summaries

      _ ->
        []
    end
  end

  defp get_address_from_summary(%BeaconSummary{subset: subset, summary_time: summary_time}) do
    Crypto.derive_beacon_chain_address(subset, summary_time, true)
  end

  defp load_downloaded_summary(%BeaconSummary{summary_time: summary_time, subset: subset}) do
    node_list = P2P.distinct_nodes([P2P.get_node_info() | P2P.authorized_nodes()])

    beacon_storage_nodes = Election.beacon_storage_nodes(subset, summary_time, node_list)
    address = Crypto.derive_beacon_chain_address(subset, summary_time, true)

    with true <- Utils.key_in_node_list?(beacon_storage_nodes, Crypto.first_node_public_key()),
         false <- TransactionChain.transaction_exists?(address),
         {:ok, tx} <- fetch_transaction(beacon_storage_nodes, address) do
      TransactionChain.write_transaction(tx)
    end
  end

  def download_summary(_beacon_address, [], _), do: {:ok, %NotFound{}}

  def download_summary(beacon_address, nodes, patch) do
    nodes
    |> P2P.nearest_nodes(patch)
    |> do_get_download_summary(beacon_address, nil)
  end

  defp do_get_download_summary([node | rest], address, prev_result) do
    case P2P.send_message(node, %GetBeaconSummary{address: address}) do
      {:ok, summary = %BeaconSummary{}} ->
        {:ok, summary}

      {:ok, %NotFound{}} ->
        do_get_download_summary(rest, address, %NotFound{})

      {:error, _} ->
        do_get_download_summary(rest, address, prev_result)
    end
  end

  defp do_get_download_summary([], _, %NotFound{}), do: {:ok, %NotFound{}}
  defp do_get_download_summary([], _, _), do: {:error, :network_issue}

  defp fetch_transaction([node | rest], address) do
    case P2P.send_message(node, %GetTransaction{address: address}) do
      {:ok, tx = %Transaction{}} ->
        {:ok, tx}

      _ ->
        fetch_transaction(rest, address)
    end
  end

  defp fetch_transaction([], address) do
    Logger.error("Cannot fetch beacon summary transaction to store",
      transaction_address: Base.encode16(address),
      type: :beacon_summary
    )

    {:error, :network_issue}
  end

  @doc """
  Process beacon summaries to synchronize the transactions involving.

  Each transactions from the beacon summaries will be analyzed to determine
  if the node is a storage node for this transaction. If so, it will download the
  transaction from the closest storage nodes and replicate it locally.

  The P2P view will also be updated if some node information are inside the beacon chain to determine
  the readiness or the availability of a node.

  Also, the  number of transaction received during the beacon summary interval will be stored.
  """
  @spec handle_missing_summaries(Enumerable.t() | list(BeaconSummary.t()), binary()) :: :ok
  def handle_missing_summaries(summaries, node_patch) when is_binary(node_patch) do
    initial_state = %{transactions: [], ends_of_sync: [], stats: %{}, p2p_availabilities: []}

    summaries
    |> Enum.reduce(initial_state, &aggregate_summary/2)
    |> process_summary_aggregate(node_patch)
  end

  defp aggregate_summary(
         summary = %BeaconSummary{
           transaction_summaries: transaction_summaries,
           end_of_node_synchronizations: ends_of_sync,
           summary_time: summary_time
         },
         acc
       ) do
    acc
    |> Map.update!(:transactions, &(&1 ++ transaction_summaries))
    |> Map.update!(:ends_of_sync, &(&1 ++ ends_of_sync))
    |> Map.update!(
      :p2p_availabilities,
      &(&1 ++ BeaconSummary.get_node_availabilities(summary, P2P.list_nodes()))
    )
    |> update_in([:stats, Access.key(summary_time, 0)], &(&1 + length(transaction_summaries)))
  end

  defp process_summary_aggregate(
         %{
           transactions: transactions,
           ends_of_sync: ends_of_sync,
           stats: stats,
           p2p_availabilities: p2p_availabilities
         },
         node_patch
       ) do
    synchronize_transactions(transactions, node_patch)

    Enum.each(ends_of_sync, &handle_end_of_node_sync/1)

    Enum.each(p2p_availabilities, &update_availabilities(elem(&1, 0), elem(&1, 1), elem(&1, 2)))

    update_statistics(stats)
  end

  defp synchronize_transactions(transaction_summaries, node_patch) do
    transactions_to_sync =
      transaction_summaries
      |> Enum.uniq_by(& &1.address)
      |> Enum.sort_by(& &1.timestamp, {:asc, DateTime})
      |> Enum.reject(&TransactionChain.transaction_exists?(&1.address))
      |> Enum.filter(&TransactionHandler.download_transaction?/1)

    Logger.info("Need to synchronize #{Enum.count(transactions_to_sync)} transactions")
    Logger.debug("Transaction to sync #{inspect(transactions_to_sync)}")

    Enum.each(transactions_to_sync, &TransactionHandler.download_transaction(&1, node_patch))
  end

  defp handle_end_of_node_sync(%EndOfNodeSync{public_key: node_public_key, timestamp: timestamp}) do
    DB.register_p2p_summary(node_public_key, timestamp, true, 1.0)
    P2P.set_node_globally_available(node_public_key)
  end

  defp update_availabilities(%Node{first_public_key: node_key}, available?, avg_availability) do
    DB.register_p2p_summary(node_key, DateTime.utc_now(), available?, avg_availability)

    if available? do
      P2P.set_node_globally_available(node_key)
    else
      P2P.set_node_globally_unavailable(node_key)
    end

    P2P.set_node_average_availability(node_key, avg_availability)
  end

  defp update_statistics(stats) do
    Enum.each(stats, fn {date, nb_transactions} ->
      previous_summary_time =
        date
        |> Utils.truncate_datetime()
        |> BeaconChain.previous_summary_time()

      nb_seconds = abs(DateTime.diff(previous_summary_time, date))
      tps = nb_transactions / nb_seconds

      DB.register_tps(date, tps, nb_transactions)

      Logger.info(
        "TPS #{tps} on #{Utils.time_to_string(date)} with #{nb_transactions} transactions"
      )

      PubSub.notify_new_tps(tps, nb_transactions)
    end)
  end
end
