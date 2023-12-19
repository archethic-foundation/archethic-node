defmodule ArchethicWeb.Explorer.DashboardLive do
  @moduledoc """
  Live-View for Network-Metric-Dashboard
  """
  use ArchethicWeb.Explorer, :live_view

  alias ArchethicWeb.DashboardMetricsAggregator
  alias ArchethicWeb.Explorer.DashboardView

  alias Phoenix.View

  def mount(_params, _session, socket) do
    if connected?(socket) do
      # start the tick loop
      Process.send_after(self(), :tick, 30_000)
    end

    version = Application.spec(:archethic, :vsn)
    stats = fetch_stats()

    {:ok,
     socket
     |> assign(version: version)
     |> push_event("network_transactions_count", network_transactions_count(stats))
     |> push_event("node_transactions_count", node_transactions_count(stats))
     |> push_event("node_transactions_avg_duration", node_transactions_avg_duration(stats))}
  end

  def render(assigns) do
    View.render(DashboardView, "dashboard.html", assigns)
  end

  def handle_info(:tick, socket) do
    # continue the tick loop
    Process.send_after(self(), :tick, 30_000)

    # fetch data
    stats = fetch_stats()

    {:noreply,
     socket
     |> push_event("network_transactions_count", network_transactions_count(stats))
     |> push_event("node_transactions_count", node_transactions_count(stats))
     |> push_event("node_transactions_avg_duration", node_transactions_avg_duration(stats))}
  end

  def display_time(datetime) do
    "#{zero_pad(datetime.hour)}:#{zero_pad(datetime.minute)}:#{zero_pad(datetime.second)} UTC"
  end

  def stats_to_nodes(stats) do
    stats
    |> Enum.reduce(MapSet.new(), fn {{node, _datetime}, _durations}, acc ->
      MapSet.put(acc, node)
    end)
    |> MapSet.to_list()
  end

  defp fetch_stats() do
    # DashboardMetricsAggregator returns an _UNORDERED_ map
    # we convert it to a ORDERED list of pairs
    DashboardMetricsAggregator.get_all()
    |> Enum.map(fn {{node_public_key, datetime}, durations_by_address} ->
      {{Base.encode16(node_public_key), datetime}, durations_by_address}
    end)
    |> Enum.sort(fn {{_, datetime_a}, _}, {{_, datetime_b}, _} ->
      DateTime.compare(datetime_a, datetime_b) != :gt
    end)
  end

  defp network_transactions_count(stats) do
    stats
    |> Enum.reduce(%{}, fn {{_node, datetime}, durations_by_address}, acc ->
      addresses_set =
        durations_by_address
        |> Enum.map(&elem(&1, 0))
        |> MapSet.new()

      Map.update(
        acc,
        DateTime.to_unix(datetime),
        addresses_set,
        &MapSet.union(&1, addresses_set)
      )
    end)
    |> Enum.map(fn {timestamp, addresses_set} ->
      {timestamp, MapSet.size(addresses_set)}
    end)
    |> Enum.into(%{})
  end

  defp node_transactions_count(stats) do
    Enum.reduce(stats, %{}, fn {{node, datetime}, durations_by_address}, acc ->
      timestamp = DateTime.to_unix(datetime)
      count = length(durations_by_address)
      default = %{timestamps: [timestamp], counts: [count]}

      Map.update(acc, node, default, fn %{timestamps: timestamps_acc, counts: counts_acc} ->
        %{timestamps: [timestamp | timestamps_acc], counts: [count | counts_acc]}
      end)
    end)
    |> Enum.map(fn {node, %{timestamps: timestamps, counts: counts}} ->
      {node, %{timestamps: Enum.reverse(timestamps), counts: Enum.reverse(counts)}}
    end)
    |> Enum.into(%{})
  end

  defp node_transactions_avg_duration(stats) do
    Enum.reduce(stats, %{}, fn {{node, datetime}, durations_by_address}, acc ->
      timestamp = DateTime.to_unix(datetime)

      durations = Enum.map(durations_by_address, &elem(&1, 1))
      count = length(durations)

      average_duration =
        if count == 0 do
          0
        else
          Enum.sum(durations) / count
        end

      default = %{timestamps: [timestamp], average_durations: [average_duration]}

      Map.update(acc, node, default, fn %{
                                          timestamps: timestamps_acc,
                                          average_durations: average_durations_acc
                                        } ->
        %{
          timestamps: [timestamp | timestamps_acc],
          average_durations: [average_duration | average_durations_acc]
        }
      end)
    end)
    |> Enum.map(fn {node, %{timestamps: timestamps, average_durations: average_durations}} ->
      {node,
       %{timestamps: Enum.reverse(timestamps), average_durations: Enum.reverse(average_durations)}}
    end)
    |> Enum.into(%{})
  end
end
