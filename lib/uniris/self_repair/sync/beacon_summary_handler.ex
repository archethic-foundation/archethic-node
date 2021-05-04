defmodule Uniris.SelfRepair.Sync.BeaconSummaryHandler do
  @moduledoc false

  alias Uniris.BeaconChain
  alias Uniris.BeaconChain.Slot, as: BeaconSlot
  alias Uniris.BeaconChain.Slot.TransactionSummary
  alias Uniris.BeaconChain.Slot.EndOfNodeSync
  alias Uniris.BeaconChain.Summary, as: BeaconSummary

  alias Uniris.Crypto

  alias Uniris.DB

  alias Uniris.Election

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetBeaconSlot
  alias Uniris.P2P.Message.GetBeaconSummary

  alias __MODULE__.NetworkStatistics
  alias __MODULE__.TransactionHandler

  alias Uniris.TransactionChain

  alias Uniris.Utils

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
        do_fetch_summary(subset, summary_time, nodes, patch)
      end,
      on_timeout: :kill_task,
      max_concurrency: 256
    )
    |> Stream.filter(&match?({:ok, {:ok, %BeaconSummary{}}}, &1))
    |> Stream.map(fn {:ok, {:ok, res}} -> res end)
  end

  defp do_fetch_summary(subset, summary_time, nodes, patch) do
    if Utils.key_in_node_list?(nodes, Crypto.node_public_key(0)) do
      case DB.get_beacon_summary(subset, summary_time) do
        {:ok, summary} ->
          {:ok, summary}

        _ ->
          # If the node did not receive the beacon summary it can request another remote node
          # to find it
          download_summary(nodes, subset, summary_time, patch)
      end
    else
      download_summary(nodes, subset, summary_time, patch)
    end
  end

  defp download_summary(nodes, subset, summary_time, patch) do
    nodes
    |> Enum.reject(&(&1.first_public_key == Crypto.node_public_key(0)))
    |> P2P.reply_atomic(3, %GetBeaconSummary{subset: subset, date: summary_time}, patch: patch)
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
        P2P.reply_atomic(nodes, 3, %GetBeaconSlot{subset: subset, slot_time: slot_time},
          patch: patch
        )
      end,
      on_timeout: :kill_task,
      max_concurrency: 256
    )
    |> Stream.filter(&match?({:ok, {:ok, %BeaconSlot{}}}, &1))
    |> Stream.map(fn {:ok, {:ok, res}} -> res end)
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
    nb_transactions_by_times =
      Enum.reduce(
        summaries,
        %{},
        fn summary = %BeaconSummary{
             transaction_summaries: transactions,
             summary_time: summary_time
           },
           acc ->
          load_summary_in_db(summary)
          do_handle_missing_summary(summary, node_patch)

          Map.update(acc, summary_time, length(transactions), &(&1 + length(transactions)))
        end
      )

    Enum.each(nb_transactions_by_times, fn {time, nb_transactions} ->
      update_statistics(time, nb_transactions)
    end)
  end

  defp do_handle_missing_summary(
         %BeaconSummary{
           transaction_summaries: transaction_summaries,
           end_of_node_synchronizations: end_of_syncs
         },
         node_patch
       ) do
    (transaction_summaries ++ end_of_syncs)
    |> Enum.sort_by(& &1.timestamp, {:asc, DateTime})
    |> Enum.each(&handle_update(&1, node_patch))
  end

  defp handle_update(tx_summary = %TransactionSummary{address: address, type: type}, node_patch) do
    with false <- TransactionChain.transaction_exists?(address),
         true <- TransactionHandler.download_transaction?(tx_summary) do
      Logger.info("Need to synchronize #{type}@#{Base.encode16(address)}")
      TransactionHandler.download_transaction(tx_summary, node_patch)
    end
  end

  defp handle_update(%EndOfNodeSync{public_key: public_key}, _) do
    P2P.set_node_globally_available(public_key)
  end

  defp update_statistics(date, nb_transactions) do
    previous_date =
      date
      |> Utils.truncate_datetime()
      |> BeaconChain.previous_summary_time()

    nb_seconds = abs(DateTime.diff(previous_date, date))
    tps = nb_transactions / nb_seconds

    NetworkStatistics.register_tps(date, tps, nb_transactions)
    NetworkStatistics.increment_number_transactions(nb_transactions)
  end

  defp load_summary_in_db(summary = %BeaconSummary{subset: subset, summary_time: summary_time}) do
    node_list = [P2P.get_node_info() | P2P.authorized_nodes()] |> P2P.distinct_nodes()

    beacon_nodes =
      Election.beacon_storage_nodes(
        subset,
        summary_time,
        node_list,
        Election.get_storage_constraints()
      )

    if Utils.key_in_node_list?(beacon_nodes, Crypto.node_public_key(0)) do
      DB.register_beacon_summary(summary)
    end
  end
end
