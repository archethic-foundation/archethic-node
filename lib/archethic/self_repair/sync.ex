defmodule Archethic.SelfRepair.Sync do
  @moduledoc false

  alias Archethic.BeaconChain
  #  alias Archethic.BeaconChain.Summary, as: BeaconSummary

  alias Archethic.Crypto
  alias Archethic.DB

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetBeaconSummaries
  alias Archethic.P2P.Message.BeaconSummaryList
  alias Archethic.P2P.Node

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
  @spec last_sync_date() :: DateTime.t() | nil
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

    authorized_nodes = P2P.authorized_and_available_nodes()

    #  [0, 1, ...]    Subsets
    #     / | \ 
    #    /  |  \
    # [ ]  [ ]  [ ]  Node election
    #  |\  /|\  /|
    #  | \/ | \/ |
    #  | /\ | /\ |
    # [ ]  [ ]  [ ] Partition by node
    #  |    |    |
    # [ ]  [ ]  [ ] Aggregate addresses 
    #  |    |    |
    # [ ]  [ ]  [ ] Fetch summaries 
    #  |\  /|\  /|
    #  | \/ | \/ |
    #  | /\ | /\ |
    # [D1] [D2] [D3] Partition by date
    #  |    |    |
    # [ ]  [ ]  [ ] Aggregate and consolidate summaries 
    #  \    |    /
    #   \   |   /
    #    \  |  /
    #     \ | /
    #      [ ]

    BeaconChain.list_subsets()
    |> Flow.from_enumerable()
    |> Flow.flat_map(fn subset ->
      # Foreach subset and date we compute concurrently the node election 
      last_sync_date
      |> BeaconChain.next_summary_dates()
      |> Stream.map(&get_summary_address_by_node(&1, subset, authorized_nodes))
      |> Enum.flat_map(& &1)
    end)
    # We partition by node
    |> Flow.partition(key: {:elem, 0})
    |> Flow.reduce(fn -> %{} end, fn {node, summary_address}, acc ->
      # We aggregate the addresses for a given node
      Map.update(acc, node, [summary_address], &[summary_address | &1])
    end)
    |> Flow.flat_map(fn {node, addresses} ->
      # For this node we fetch the summaries
      fetch_summaries(node, addresses)
    end)
    # We repartition by summary time to aggregate summaries for a date
    |> Flow.partition(key: {:key, :summary_time})
    |> Flow.reduce(fn -> %BeaconSummaryAggregate{} end, fn summary, acc ->
      %{acc | summary_time: Map.get(acc, :summary_time) || summary.summary_time}
      |> BeaconSummaryAggregate.add_summary(summary)
    end)
    |> Flow.emit(:state)
    |> Stream.reject(&BeaconSummaryAggregate.empty?/1)
    |> Enum.sort_by(& &1.summary_time)
    |> Enum.each(&BeaconSummaryHandler.process_summary_aggregate(&1, patch))

    :telemetry.execute([:archethic, :self_repair], %{duration: System.monotonic_time() - start})
  end

  defp get_summary_address_by_node(date, subset, authorized_nodes) do
    filter_nodes =
      Enum.filter(authorized_nodes, &(DateTime.compare(&1.authorization_date, date) == :lt))

    summary_address = Crypto.derive_beacon_chain_address(subset, date, true)

    subset
    |> Election.beacon_storage_nodes(date, filter_nodes)
    |> Enum.map(fn node ->
      {node, summary_address}
    end)
  end

  defp fetch_summaries(node, addresses) do
    case P2P.send_message(node, %GetBeaconSummaries{addresses: addresses}) do
      {:ok, %BeaconSummaryList{summaries: summaries}} ->
        summaries

      _ ->
        []
    end
  end

  # defp subsets_by_times(time) do
  #   subsets = BeaconChain.list_subsets()
  #   Enum.map(subsets, fn subset -> {DateTime.truncate(time, :second), subset} end)
  # end

  # defp flow_window do
  #   Flow.Window.fixed(summary_interval(:second), :second, fn {date, _} ->
  #     DateTime.to_unix(date, :millisecond)
  #   end)
  # end

  # defp summary_interval(unit) do
  #   next_summary = BeaconChain.next_summary_date(DateTime.utc_now())
  #   next_summary2 = BeaconChain.next_summary_date(next_summary)
  #   DateTime.diff(next_summary2, next_summary, unit)
  # end

  # defp get_beacon_summary(time, subset, node_list) do
  #   filter_nodes = Enum.filter(node_list, &(DateTime.compare(&1.authorization_date, time) == :lt))

  #   nodes = Election.beacon_storage_nodes(subset, time, filter_nodes)
  #   BeaconSummaryHandler.get_full_beacon_summary(time, subset, nodes)
  # end
end
