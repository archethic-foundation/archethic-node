defmodule ArchEthic.Metrics.MetricNodePoller do
  @moduledoc """
  Provides Telemetry of the Node
  """
  require Logger
  use GenServer
  @default_state %{
    flag: 0,
    points: ArchEthic.Metrics.Helpers.get_metric_default_value()
  }

  def start_link(_state) do
    GenServer.start_link(__MODULE__, @default_state, name: __MODULE__)
  end

  def init(initial_state) do
    periodic_metric_aggregation()
    {:ok, initial_state}
  end

  defp periodic_metric_aggregation() do
    Process.send_after(self(), :periodic_calculation_of_points, 5_000)
  end

  def get_points() do
    GenServer.call(__MODULE__, :get_points)
  end

  def set_flag() do
    GenServer.cast(__MODULE__, :set_flag)
  end

  def unset_flag() do
    GenServer.cast(__MODULE__, :unset_flag)
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
    response = current_state
    new_state = current_state
    {:reply, response.points, new_state}
  end

  def handle_info(:periodic_calculation_of_points, current_state) do
    new_state =
        case current_state  do
          %{flag: 1 , points: _} -> %{flag: 1, points: get_new_state()}
          %{flag: 0 , points: _} -> @default_state
        end

      recheck_new_state =
          case current_state do
            %{flag: 0 , points: _} -> @default_state
            %{flag: 1 , points: _}  -> new_state
          end

    Logger.debug("METRICS : MetricNodePoller  State=#{inspect(recheck_new_state.flag)}")
    periodic_metric_aggregation()
    {:noreply, recheck_new_state}
  end

  defp get_new_state() do
    ArchEthic.Metrics.NodeMetric.run()
  end
end
