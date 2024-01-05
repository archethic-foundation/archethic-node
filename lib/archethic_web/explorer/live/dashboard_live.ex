defmodule ArchethicWeb.Explorer.DashboardLive do
  @moduledoc """
  Live-View for Network-Metric-Dashboard
  """
  use ArchethicWeb.Explorer, :live_view

  alias Archethic.Utils
  alias ArchethicWeb.DashboardMetricsAggregator

  def mount(_params, _session, socket) do
    if connected?(socket) do
      # start the tick loop
      Process.send_after(self(), :tick, 30_000)
    end

    # TODO: check if it's called once or twice

    version = Application.spec(:archethic, :vsn)
    stats = fetch_stats()

    {:ok,
     socket
     |> assign(version: version)
     |> push_event("boxplot_transactions_avg_duration", boxplot_transactions_avg_duration(stats))
     |> push_event("network_transactions_count", network_transactions_count(stats))
     |> push_event("network_transactions_avg_duration", network_transactions_avg_duration(stats))
     |> push_event("node_transactions_count", node_transactions_count(stats))}
  end

  def handle_info(:tick, socket) do
    # continue the tick loop
    Process.send_after(self(), :tick, 30_000)

    # fetch data
    stats = fetch_stats()

    {:noreply,
     socket
     |> push_event("boxplot_transactions_avg_duration", boxplot_transactions_avg_duration(stats))
     |> push_event("network_transactions_count", network_transactions_count(stats))
     |> push_event("network_transactions_avg_duration", network_transactions_avg_duration(stats))
     |> push_event("node_transactions_count", node_transactions_count(stats))}
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
    |> Enum.map(fn {{node_public_key, datetime}, duration_by_address} ->
      {{Base.encode16(node_public_key), datetime}, duration_by_address}
    end)
    |> Enum.sort_by(fn {{_, datetime}, _} -> datetime end, {:asc, DateTime})
  end

  defp boxplot_transactions_avg_duration(stats) do
    stats
    |> Enum.reduce(%{}, fn {{_node, datetime}, duration_by_address}, acc ->
      durations =
        duration_by_address
        |> Enum.map(&elem(&1, 1))

      Map.update(
        acc,
        DateTime.to_unix(datetime),
        durations,
        &(&1 ++ durations)
      )
    end)
    |> Enum.map(fn {timestamp, durations} ->
      durations_length = length(durations)

      sorted = Enum.sort(durations)
      min = List.first(sorted)
      max = List.last(sorted)
      q2 = Utils.median(sorted, sorted: true)
      q1 = Utils.median(Enum.take(sorted, div(durations_length, 2)), sorted: true)
      q3 = Utils.median(Enum.drop(sorted, div(durations_length + 1, 2)), sorted: true)

      {timestamp, [min, q1, q2, q3, max]}
    end)
    |> Enum.into(%{})
  end

  defp network_transactions_count(stats) do
    stats
    |> Enum.reduce(%{}, fn {{_node, datetime}, duration_by_address}, acc ->
      addresses_set =
        duration_by_address
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

  defp network_transactions_avg_duration(stats) do
    stats
    |> Enum.reduce(%{}, fn {{_node, datetime}, duration_by_address}, acc ->
      durations =
        duration_by_address
        |> Enum.map(&elem(&1, 1))

      cur_count = length(durations)
      cur_sum = Enum.sum(durations)

      Map.update(
        acc,
        DateTime.to_unix(datetime),
        %{count: cur_count, sum: cur_sum},
        fn %{count: count, sum: sum} ->
          %{count: count + cur_count, sum: sum + cur_sum}
        end
      )
    end)
    |> Enum.map(fn
      {timestamp, %{count: 0, sum: 0}} ->
        {timestamp, 0}

      {timestamp, %{count: count, sum: sum}} ->
        {timestamp, sum / count}
    end)
    |> Enum.into(%{})
  end

  defp node_transactions_count(stats) do
    Enum.reduce(stats, %{}, fn {{node, _datetime}, duration_by_address}, acc ->
      count = length(duration_by_address)

      Map.update(
        acc,
        node,
        count,
        &(&1 + count)
      )
    end)
  end
end
