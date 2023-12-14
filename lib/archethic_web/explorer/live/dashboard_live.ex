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
     |> assign(
       version: version,
       stats: stats
     )
     |> push_event("network_updates", network_aggregate(stats))
     |> push_event("node_updates", node_aggregate(stats))}
  end

  def render(assigns) do
    View.render(DashboardView, "dashboard.html", assigns)
  end

  def handle_info(:tick, socket) do
    # continue the tick loop
    Process.send_after(self(), :tick, 30_000)

    # fetch data
    version = Application.spec(:archethic, :vsn)
    stats = fetch_stats()

    {:noreply,
     socket
     |> assign(version: version, stats: stats)
     |> push_event("network_updates", network_aggregate(stats))
     |> push_event("node_updates", node_aggregate(stats))}
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
    DashboardMetricsAggregator.get_all()
    |> Enum.map(fn {{node_public_key, datetime}, durations} ->
      {{Base.encode16(node_public_key), datetime}, durations}
    end)
    |> Enum.into(%{})
  end

  defp network_aggregate(stats) do
    Enum.reduce(stats, %{}, fn {{_node, datetime}, durations}, acc ->
      Map.update(acc, DateTime.to_unix(datetime), durations, &(&1 ++ durations))
    end)
  end

  defp node_aggregate(stats) do
    Enum.reduce(stats, %{}, fn {{node, datetime}, durations}, acc ->
      timestamp = DateTime.to_unix(datetime)
      default = %{timestamps: [timestamp], durations: [durations]}

      Map.update(acc, node, default, fn %{
                                          timestamps: timestamps_acc,
                                          durations: durations_acc
                                        } ->
        %{timestamps: [timestamp | timestamps_acc], durations: [durations | durations_acc]}
      end)
    end)
  end
end
