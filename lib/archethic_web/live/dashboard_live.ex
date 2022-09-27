defmodule ArchethicWeb.DashboardLive do
  @moduledoc """
  Live-View for Network-Metric-Dashboard
  """
  use ArchethicWeb, :live_view

  alias Archethic.Metrics.Poller
  alias ArchethicWeb.DashboardView

  alias Phoenix.View

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Poller.monitor()
      Process.send_after(self(), :aggregate, 5_000)
    end

    version = Application.spec(:archethic, :vsn)

    Task.async(fn ->
      Poller.fetch_metrics()
      |> Stream.filter(&match?({:ok, {_, {:ok, _}}}, &1))
      |> Enum.reduce(%{}, fn {:ok, {node, {:ok, metrics}}}, acc ->
        Map.put(
          acc,
          node,
          Enum.reduce(
            metrics,
            default_node_metric(),
            &cumul(&2, &1)
          )
        )
      end)
    end)
    
    new_socket =
      socket
      |> assign(:version, version)
      |> assign(:stats, %{})

    {:ok, new_socket}
  end
  
  def handle_info({_ref, stats}, socket) do
    {:noreply, assign(socket, :stats, stats)}
  end
  
  def handle_info({:DOWN, _ref, :process, _, _}, socket), do: {:noreply, socket}

  def handle_info(:aggregate, socket = %{assigns: %{stats: stats}}) do
    Process.send_after(self(), :aggregate, 5_000)

    %{tx_processed: tx_processed, validation_duration: validation_duration} =
      Enum.reduce(stats, %{tx_processed: 0, validation_duration: 0}, fn {_node,
                                                                         %{
                                                                           nb_transactions:
                                                                             nb_transactions,
                                                                           validation_duration:
                                                                             validation_duration
                                                                         }},
                                                                        acc ->
        acc
        |> Map.update!(:tx_processed, &(&1 + nb_transactions))
        |> Map.update!(:validation_duration, &(&1 + validation_duration))
      end)

    avg_nb_transactions = tx_processed / map_size(stats)
    avg_duration = validation_duration / map_size(stats)

    new_socket =
      socket
      |> push_event("network_updates", %{
        nb_transactions: avg_nb_transactions,
        validation_duration: avg_duration
      })

    {:noreply, new_socket}
  end

  def handle_info({:update_data, data, public_key}, socket = %{assigns: %{stats: stats}}) do
    new_data =
      case Map.get(stats, public_key) do
        nil ->
          Enum.reduce(data, default_node_metric(), fn metric, acc ->
            acc
            |> aggregate(metric)
            |> cumul(metric)
          end)
          |> Enum.into(%{})

        previous_data ->
          Enum.reduce(data, previous_data, fn metric, acc ->
            acc
            |> aggregate(metric)
            |> cumul(metric)
          end)
          |> Enum.into(%{})
      end

    new_socket =
      socket
      |> update(:stats, &Map.put(&1, public_key, new_data))

    {:noreply, new_socket}
  end

  def render(assigns) do
    View.render(DashboardView, "dashboard.html", assigns)
  end

  defp aggregate(
         acc,
         {"archethic_mining_full_transaction_validation_duration", %{count: count, sum: sum}}
       ) do
    {acc_count, acc_sum} =
      get_in(acc, [Access.key(:cumul, %{}), :transaction_validation]) || {0, 0}

    new_count = count - acc_count
    new_sum = sum - acc_sum

    new_tps =
      if new_sum > 0 do
        new_count / new_sum
      else
        0.0
      end

    acc
    |> Map.put(:nb_transactions, new_count)
    |> Map.put(:tps, Float.round(new_tps, 2))
    |> Map.put(:validation_duration, new_sum)
  end

  defp aggregate(acc, _), do: acc

  defp cumul(
         acc,
         {"archethic_mining_full_transaction_validation_duration", %{count: count, sum: sum}}
       ) do
    put_in(acc, [Access.key(:cumul, %{}), :transaction_validation], {count, sum})
  end

  defp cumul(acc, _), do: acc
  
  defp default_node_metric do
    %{
      nb_transactions: 0,
      tps: 0.0,
      validation_duration: 0,
      cumul: %{transaction_validation: {0, 0}}
    }
  end
end
