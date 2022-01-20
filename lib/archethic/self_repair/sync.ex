defmodule ArchEthic.SelfRepair.Sync do
  @moduledoc false

  alias ArchEthic.BeaconChain
  alias ArchEthic.BeaconChain.Summary, as: BeaconSummary

  alias ArchEthic.DB

  alias ArchEthic.Election

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node

  alias __MODULE__.BeaconSummaryHandler
  alias __MODULE__.BeaconSummaryAggregate

  require Logger

  @bootstrap_info_last_sync_date_key "last_sync_time"

  @doc """
  Return the last synchronization date from the previous cycle of self repair

  If there are not previous stored date:
   - Try to the first enrollment date of the listed nodes
   - Otherwise take the current date
  """
  @spec last_sync_date() :: DateTime.t()
  def last_sync_date do
    case DB.get_bootstrap_info(@bootstrap_info_last_sync_date_key) do
      nil ->
        Logger.info("Not previous synchronization date")
        Logger.info("We are using the default one")
        default_last_sync_date()

      timestamp ->
        date =
          timestamp
          |> String.to_integer()
          |> DateTime.from_unix!()

        Logger.info("Last synchronization date #{DateTime.to_string(date)}")
        date
    end
  end

  defp default_last_sync_date do
    case P2P.authorized_nodes() do
      [] ->
        nil

      nodes ->
        %Node{enrollment_date: enrollment_date} =
          nodes
          |> Enum.reject(&(&1.enrollment_date == nil))
          |> Enum.sort_by(& &1.enrollment_date)
          |> Enum.at(0)

        Logger.info(
          "We are taking the first node's enrollment date - #{DateTime.to_string(enrollment_date)}"
        )

        enrollment_date
    end
  end

  @doc """
  Persist the last sync date
  """
  @spec store_last_sync_date(DateTime.t()) :: :ok
  def store_last_sync_date(date = %DateTime{}) do
    timestamp =
      date
      |> DateTime.to_unix()
      |> Integer.to_string()

    DB.set_bootstrap_info(@bootstrap_info_last_sync_date_key, timestamp)

    Logger.info("Last sync date updated: #{DateTime.to_string(date)}")
  end

  @doc """
  Retrieve missing transactions from the missing beacon chain slots
  since the last sync date provided

  Beacon chain pools are retrieved from the given latest synchronization
  date including all the beacon subsets (i.e <<0>>, <<1>>, etc.)

  Once retrieved, the transactions are downloaded and stored if not exists locally
  """
  @spec load_missed_transactions(
          last_sync_date :: DateTime.t(),
          patch :: binary()
        ) :: :ok
  def load_missed_transactions(last_sync_date = %DateTime{}, patch) when is_binary(patch) do
    Logger.info(
      "Fetch missed transactions from last sync date: #{DateTime.to_string(last_sync_date)}"
    )

    start = System.monotonic_time()

    authorized_nodes = P2P.authorized_nodes()

    last_sync_date
    |> BeaconChain.next_summary_dates()
    |> Flow.from_enumerable()
    |> Flow.flat_map(&subsets_by_times/1)
    |> Flow.partition(key: {:elem, 0})
    |> Flow.reduce(
      fn -> %BeaconSummaryAggregate{} end,
      &aggregate_summaries_by_date(&1, &2, authorized_nodes)
    )
    |> Flow.emit(:state)
    |> Stream.reject(&BeaconSummaryAggregate.empty?/1)
    |> Enum.sort_by(& &1.summary_time)
    |> Enum.each(&BeaconSummaryHandler.process_summary_aggregate(&1, patch))

    :telemetry.execute([:archethic, :self_repair], %{duration: System.monotonic_time() - start})
  end

  defp subsets_by_times(time) do
    subsets = BeaconChain.list_subsets()
    Enum.map(subsets, fn subset -> {DateTime.truncate(time, :second), subset} end)
  end

  # defp flow_window do
  #   Flow.Window.fixed(, :second, fn {date, _} ->
  #     DateTime.to_unix(date, :millisecond)
  #   end)
  # end

  # defp dates_interval_seconds(last_sync_date) do
  #   DateTime.diff(last_sync_date, BeaconChain.next_summary_date(last_sync_date))
  # end

  defp get_beacon_summary(time, subset, node_list) do
    filter_nodes = Enum.filter(node_list, &(DateTime.compare(&1.authorization_date, time) == :lt))

    nodes = Election.beacon_storage_nodes(subset, time, filter_nodes)
    BeaconSummaryHandler.get_full_beacon_summary(time, subset, nodes)
  end

  defp aggregate_summaries_by_date({time, subset}, acc, authorized_nodes) do
    summary = get_beacon_summary(time, subset, authorized_nodes)

    if BeaconSummary.empty?(summary) do
      acc
    else
      acc
      |> BeaconSummaryAggregate.initialize(summary)
      |> BeaconSummaryAggregate.add_transaction_summaries(summary)
      |> BeaconSummaryAggregate.add_p2p_availabilities(summary)
    end
  end
end
