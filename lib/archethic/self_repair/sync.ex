defmodule ArchEthic.SelfRepair.Sync do
  @moduledoc false

  alias ArchEthic.BeaconChain
  alias ArchEthic.BeaconChain.Summary, as: BeaconSummary

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node

  alias __MODULE__.BeaconSummaryHandler

  alias ArchEthic.Utils

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
        default_last_sync_date()

      date ->
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
        DateTime.utc_now()

      nodes ->
        %Node{enrollment_date: enrollment_date} =
          nodes
          |> Enum.reject(&(&1.enrollment_date == nil))
          |> Enum.sort_by(& &1.enrollment_date)
          |> Enum.at(0)

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
          patch :: binary(),
          bootstrap? :: boolean()
        ) :: :ok
  def load_missed_transactions(last_sync_date = %DateTime{}, patch, bootstrap? \\ false)
      when is_binary(patch) and is_boolean(bootstrap?) do
    Logger.info(
      "Fetch missed transactions from last sync date: #{DateTime.to_string(last_sync_date)}"
    )

    if bootstrap? do
      Stream.concat(
        missed_previous_slots(patch),
        missed_previous_summaries(last_sync_date, patch)
      )
    else
      missed_previous_summaries(last_sync_date, patch)
    end
    |> BeaconSummaryHandler.handle_missing_summaries(patch)
  end

  defp missed_previous_summaries(last_sync_date, patch) do
    last_sync_date
    |> BeaconChain.get_summary_pools()
    |> BeaconSummaryHandler.get_beacon_summaries(patch)
  end

  defp missed_previous_slots(patch) do
    DateTime.utc_now()
    |> BeaconChain.previous_summary_time()
    |> BeaconChain.get_slot_pools()
    |> BeaconSummaryHandler.get_beacon_slots(patch)
    |> Stream.map(&BeaconSummary.from_slot/1)
  end
end
