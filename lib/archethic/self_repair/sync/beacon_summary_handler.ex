defmodule ArchEthic.SelfRepair.Sync.BeaconSummaryHandler do
  @moduledoc false

  alias ArchEthic.BeaconChain
  alias ArchEthic.BeaconChain.Slot, as: BeaconSlot
  alias ArchEthic.BeaconChain.Summary, as: BeaconSummary

  alias ArchEthic.Crypto

  alias ArchEthic.DB

  alias ArchEthic.Election

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.GetTransaction
  alias ArchEthic.P2P.Message.NotFound
  alias ArchEthic.P2P.Node

  alias ArchEthic.PubSub

  alias __MODULE__.TransactionHandler

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData

  alias ArchEthic.Utils

  require Logger

  @doc """
  Retrieve the list of missed beacon summaries from a given date.

  It request every subsets to find out the missing ones by querying beacon pool nodes.
  """
  @spec get_beacon_summaries(BeaconChain.pools(), binary()) :: Enumerable.t()
  def get_beacon_summaries(summary_pools, patch) when is_binary(patch) do
    Enum.map(summary_pools, fn {subset, nodes_by_summary_time} ->
      Enum.map(nodes_by_summary_time, fn {summary_time, nodes} ->
        {nodes, subset, summary_time}
      end)
    end)
    |> :lists.flatten()
    |> Task.async_stream(
      fn {nodes, subset, summary_time} ->
        beacon_address = Crypto.derive_beacon_chain_address(subset, summary_time, true)

        beacon_address
        |> download_summary(nodes, patch)
        |> handle_summary_transaction(subset, summary_time, nodes, beacon_address)
      end,
      on_timeout: :kill_task,
      max_concurrency: 256
    )
    |> Stream.filter(&match?({:ok, %Transaction{}}, &1))
    |> Stream.map(fn {:ok, %Transaction{data: %TransactionData{content: content}}} ->
      {summary, _} = BeaconSummary.deserialize(content)
      summary
    end)
  end

  defp download_summary(beacon_address, nodes, patch) do
    case Enum.reject(nodes, &(&1.first_public_key == Crypto.first_node_public_key())) do
      [] ->
        if Utils.key_in_node_list?(nodes, Crypto.first_node_public_key()) do
          TransactionChain.get_transaction(beacon_address)
        else
          {:error, :network_issue}
        end

      remote_nodes ->
        P2P.reply_atomic(remote_nodes, 3, %GetTransaction{address: beacon_address},
          patch: patch,
          compare_fun: fn
            %Transaction{data: %TransactionData{content: content}} -> content
            %NotFound{} -> :not_found
          end
        )
    end
  end

  defp handle_summary_transaction({:ok, tx}, subset, summary_time, nodes, _beacon_address) do
    beacon_storage_nodes =
      Election.beacon_storage_nodes(subset, summary_time, [P2P.get_node_info() | nodes])

    with true <- Utils.key_in_node_list?(beacon_storage_nodes, Crypto.first_node_public_key()),
         false <- TransactionChain.transaction_exists?(tx.address) do
      TransactionChain.write_transaction(tx)
    end

    tx
  end

  defp handle_summary_transaction({:error, :transaction_not_exists}, _, _, _, _) do
    {:error, :transaction_not_exists}
  end

  defp handle_summary_transaction(
         {:error, :network_issue},
         _subset,
         _summary_time,
         nodes,
         beacon_address
       ) do
    Logger.error("Cannot fetch during self repair from #{inspect(nodes)}",
      transaction: "summary@#{Base.encode16(beacon_address)}"
    )

    {:error, :network_issue}
  end

  @doc """
  Retrieve the list of missed beacon summaries slots a given date.

  It request every subsets to find out the missing ones by querying beacon pool nodes.
  """
  @spec get_beacon_slots(BeaconChain.pools(), binary()) :: Enumerable.t()
  def get_beacon_slots(slot_pools, patch) do
    Enum.map(slot_pools, fn {subset, nodes_by_slot_time} ->
      Enum.map(nodes_by_slot_time, fn {slot_time, nodes} ->
        {nodes, subset, slot_time}
      end)
    end)
    |> :lists.flatten()
    |> Task.async_stream(
      fn {nodes, subset, slot_time} ->
        beacon_address = Crypto.derive_beacon_chain_address(subset, slot_time)
        P2P.reply_atomic(nodes, 3, %GetTransaction{address: beacon_address}, patch: patch)
      end,
      on_timeout: :kill_task,
      max_concurrency: 256
    )
    |> Stream.filter(&match?({:ok, {:ok, %Transaction{}}}, &1))
    |> Stream.map(fn {:ok, {:ok, %Transaction{data: %TransactionData{content: content}}}} ->
      {slot, _} = BeaconSlot.deserialize(content)
      slot
    end)
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
    %{
      transactions: transactions,
      ends_of_sync: ends_of_sync,
      stats: stats,
      p2p_availabilities: p2p_availabilities
    } = reduce_summaries(summaries)

    synchronize_transactions(transactions, node_patch)

    Enum.each(ends_of_sync, &P2P.set_node_globally_available(&1.public_key))

    Enum.each(p2p_availabilities, fn
      {%Node{first_public_key: node_key}, true} ->
        P2P.set_node_globally_available(node_key)

      {%Node{first_public_key: node_key}, false} ->
        P2P.set_node_globally_unavailable(node_key)
    end)

    update_statistics(stats)
  end

  defp reduce_summaries(summaries) do
    Enum.reduce(
      summaries,
      %{transactions: [], ends_of_sync: [], stats: %{}, p2p_availabilities: []},
      &do_reduce_summary/2
    )
    |> Map.update!(:transactions, &List.flatten/1)
    |> Map.update!(:ends_of_sync, &List.flatten/1)
    |> Map.update!(:p2p_availabilities, &List.flatten/1)
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
    |> Map.update!(:transactions, &[transaction_summaries | &1])
    |> Map.update!(:ends_of_sync, &[ends_of_sync | &1])
    |> Map.update!(:p2p_availabilities, &[BeaconSummary.get_node_availabilities(summary) | &1])
    |> update_in([:stats, Access.key(summary_time, 0)], &(&1 + length(transaction_summaries)))
  end

  defp synchronize_transactions(transaction_summaries, node_patch) do
    transactions_to_sync =
      transaction_summaries
      |> Enum.uniq_by(& &1.address)
      |> Enum.sort_by(& &1.timestamp)
      |> Enum.reject(&TransactionChain.transaction_exists?(&1.address))
      |> Enum.filter(&TransactionHandler.download_transaction?/1)

    Logger.info("Need to synchronize #{Enum.count(transactions_to_sync)} transactions")

    Enum.each(transactions_to_sync, &TransactionHandler.download_transaction(&1, node_patch))
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
