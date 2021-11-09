defmodule ArchEthic.SelfRepair.Sync.BeaconSummaryHandler do
  @moduledoc false

  alias ArchEthic.BeaconChain
  alias ArchEthic.BeaconChain.Slot.EndOfNodeSync
  alias ArchEthic.BeaconChain.Summary, as: BeaconSummary

  alias ArchEthic.Crypto

  alias ArchEthic.DB

  alias ArchEthic.Election

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.GetBeaconSummary
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

  It request every subsets to find out the missing ones by querying beacon pool nodes.
  """
  @spec get_beacon_summaries(Enumerable.t(), binary()) :: Enumerable.t()
  def get_beacon_summaries(summary_pools, patch) when is_binary(patch) do
    window =
      summary_pools
      |> Stream.map(&elem(&1, 0))
      |> Utils.flow_window_from_dates(&elem(&1, 0))

    summary_pools
    |> Flow.from_enumerable()
    |> Flow.partition(
      window: window,
      key: {:elem, 1}
    )
    |> Flow.map(fn {summary_time, subset, nodes} ->
      beacon_address = Crypto.derive_beacon_chain_address(subset, summary_time, true)

      beacon_address
      |> download_summary(nodes, patch)
      |> handle_summary_transaction(nodes, beacon_address)
    end)
    |> Flow.reduce(fn -> [] end, fn
      {:ok, summary = %BeaconSummary{}}, acc -> [summary | acc]
      _, acc -> acc
    end)
    |> Flow.emit(:state)
    |> Stream.transform(fn -> [] end, fn
      [], acc ->
        {[], acc}

      summaries, acc ->
        {summaries, acc}
    end)
  end

  def download_summary(beacon_address, nodes, patch, prev_result \\ nil)

  def download_summary(_beacon_address, [], _, %NotFound{}), do: {:ok, %NotFound{}}

  def download_summary(beacon_address, nodes, patch, prev_result) do
    case P2P.reply_first(nodes, %GetBeaconSummary{address: beacon_address},
           patch: patch,
           node_ack?: true
         ) do
      {:ok, %NotFound{}, node} ->
        download_summary(beacon_address, nodes -- [node], patch, %NotFound{})

      {:ok, summary = %BeaconSummary{}, _node} ->
        {:ok, summary}

      {:error, :network_issue} ->
        case prev_result do
          nil ->
            {:error, :network_issue}

          _ ->
            {:ok, prev_result}
        end
    end
  end

  defp handle_summary_transaction(
         {:ok, summary = %BeaconSummary{}},
         nodes,
         beacon_address
       ) do
    node_public_key = Crypto.first_node_public_key()

    # Load the beacon chain summary transaction if needed in background
    store_transaction_from_summary(
      beacon_address,
      summary,
      Enum.reject(nodes, &(&1.first_public_key == node_public_key))
    )

    {:ok, summary}
  end

  defp handle_summary_transaction({:ok, %NotFound{}}, _, _) do
    {:error, :not_exists}
  end

  defp handle_summary_transaction(
         {:error, :network_issue},
         nodes,
         beacon_address
       ) do
    Logger.error("Cannot fetch during self repair from #{inspect(nodes)}",
      transaction_address: Base.encode16(beacon_address),
      transaction_type: "summary"
    )

    {:error, :network_issue}
  end

  defp store_transaction_from_summary(
         address,
         %BeaconSummary{subset: subset, summary_time: summary_time},
         nodes
       ) do
    beacon_storage_nodes =
      Election.beacon_storage_nodes(subset, summary_time, [P2P.get_node_info() | nodes])

    with true <- Utils.key_in_node_list?(beacon_storage_nodes, Crypto.first_node_public_key()),
         false <- TransactionChain.transaction_exists?(address),
         {:ok, tx} <- fetch_transaction(nodes, address) do
      TransactionChain.write_transaction(tx)
    end
  end

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
  Process beacon slots to synchronize the transactions involving.

  Each transactions from the beacon slots will be analyzed to determine
  if the node is a storage node for this transaction. If so, it will download the
  transaction from the closest storage nodes and replicate it locally.

  The P2P view will also be updated if some node information are inside the beacon slots
  """
  @spec handle_missing_summaries(Enumerable.t() | list(BeaconSummary.t()), binary()) :: :ok
  def handle_missing_summaries(summaries, node_patch) when is_binary(node_patch) do
    initial_state = %{transactions: [], ends_of_sync: [], stats: %{}, p2p_availabilities: []}

    window =
      summaries
      |> Stream.uniq_by(& &1.subset)
      |> Stream.map(& &1.summary_time)
      |> Utils.flow_window_from_dates(& &1.summary_time)

    [aggregate] =
      summaries
      |> Flow.from_enumerable()
      |> Flow.partition(window: window, key: {:key, :subset})
      |> Flow.reduce(fn -> initial_state end, &do_reduce_summary/2)
      |> Flow.departition(
        &Map.new/0,
        fn new, acc ->
          acc
          |> Map.update(:transactions, new.transactions, &(&1 ++ new.transactions))
          |> Map.update(:ends_of_sync, new.ends_of_sync, &(&1 ++ new.ends_of_sync))
          |> Map.update(
            :p2p_availabilities,
            new.p2p_availabilities,
            &(&1 ++ new.p2p_availabilities)
          )
          |> Map.update(:stats, new.stats, &Map.merge(&1, new.stats))
        end,
        & &1
      )
      |> Enum.to_list()

    process_summary_aggregate(aggregate, node_patch)
  end

  defp do_reduce_summary(
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
    |> Map.update!(:p2p_availabilities, &(&1 ++ BeaconSummary.get_node_availabilities(summary)))
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

      PubSub.notify_new_tps(tps)
    end)
  end
end
