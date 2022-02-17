defmodule ArchEthic.SelfRepair.Sync do
  @moduledoc false

  alias ArchEthic.BeaconChain
  alias ArchEthic.BeaconChain.Summary, as: BeaconSummary

  alias ArchEthic.Election

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node

  alias __MODULE__.BeaconSummaryHandler
  alias __MODULE__.BeaconSummaryAggregate

  require Logger

  @doc """
  Return the last synchronization date from the previous cycle of self repair

  If there are not previous stored date:
   - Try to the first enrollment date of the listed nodes
   - Otherwise take the current date
  """
  @spec last_sync_date() :: DateTime.t()
  def last_sync_date do
    case last_sync_date_from_file() do
      nil ->
        Logger.info("Not previous synchronization date")
        Logger.info("We are using the default one")
        default_last_sync_date()

      date ->
        Logger.info("Last synchronization date #{DateTime.to_string(date)}")
        date
    end
  end

  defp last_sync_date_from_file do
    file = last_sync_file()

    if File.exists?(file) do
      content = File.read!(file)

      with {int, _} <- Integer.parse(content),
           {:ok, date} <- DateTime.from_unix(int) do
        Utils.truncate_datetime(date)
      else
        _ ->
          nil
      end
    else
      nil
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

    filename = last_sync_file()
    File.mkdir_p(Path.dirname(filename))
    File.write!(filename, timestamp, [:write])

    Logger.info("Last sync date updated: #{DateTime.to_string(date)}")
  end

  defp last_sync_file do
    relative_filepath =
      :archethic
      |> Application.get_env(__MODULE__)
      |> Keyword.get(:last_sync_file, "p2p/last_sync")

    Utils.mut_dir(relative_filepath)
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
end
