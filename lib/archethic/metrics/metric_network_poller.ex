defmodule ArchEthic.Metrics.MetricNetworkPoller do
  @moduledoc """
  Genserver Provides Telemetry of the network
  """
  require Logger
  use GenServer
  @process_name __MODULE__
  @default_state %{
    flag: 0,
    points: ArchEthic.Metrics.MetricHelperFunctions.get_client_metric_default_value()
  }

  def start_link(_state) do
    GenServer.start_link(__MODULE__, @default_state, name: @process_name)
  end

  def init(initial_state) do
    periodic_metric_aggregation()
    {:ok, initial_state}
  end

  defp periodic_metric_aggregation() do
    Process.send_after(self(), :periodic_calculation_of_points, 5_000)
  end

  def get_points() do
    GenServer.call(@process_name, :get_points)
  end

  def set_flag() do
    GenServer.cast(@process_name, :set_flag)
  end

  def unset_flag() do
    GenServer.cast(@process_name, :unset_flag)
  end

  def handle_cast(:set_flag, state) do
    new_state = %{state | flag: 1}
    {:noreply, new_state}
  end

  def handle_cast(:unset_flag, state) do
    new_state = %{state | flag: 0}
    {:noreply, new_state}
  end

  def handle_call(:get_points, _from, current_state) do
    response = current_state.points
    new_state = current_state
    {:reply, response, new_state}
  end

  def handle_info(:periodic_calculation_of_points, current_state) do
    new_state =
      case current_state.flag do
        1 -> %{flag: 1, points: get_new_state()}
        0 -> @default_state
      end

    recheck_new_state =
      case current_state.flag do
        0 -> @default_state
        1 -> new_state
      end
      Logger.debug("METRICS:MetricNetworkPoller  State=#{inspect recheck_new_state.flag}")
    periodic_metric_aggregation()
    {:noreply, recheck_new_state}
  end

  defp get_new_state() do
    ArchEthic.Metrics.NetworkMetric.run()
  end
end
