defmodule ArchEthic.Metrics.Poller do
  @moduledoc """
  Provides Telemetry of the network and Maneges
  """
  require Logger
  use GenServer
  # map because you cant pop from linked list
  @default_state %{
    pid_refs: %{},
    data: ArchEthic.Metrics.Helpers.get_client_metric_default_value()
  }

  def start_link(_state) do
    GenServer.start_link(__MODULE__, @default_state, name: __MODULE__)
  end

  def init(initial_state) do
    periodic_metric_aggregation()
    periodic_push_updates()
    {:ok, initial_state}
  end

  def periodic_metric_aggregation() do
    Process.send_after(self(), {:periodic_calculation_of_points}, 5_000)
  end

  def periodic_push_updates() do
    Process.send_after(self(), :push_updates, 251)
  end

  def send_updates(%{data: data, pid_refs: pid_refs}) do
    Enum.each(pid_refs, fn {pid_k, _pid_v} ->
      Task.start(fn ->
        send(pid_k, {:update_data, data})
      end)
    end)
  end

  def monitor() do
    GenServer.call(__MODULE__, :monitor)
  end

  def handle_call(:monitor, {pid, __tag}, state) do
    _mref = Process.monitor(pid)
    {:reply, :ok, %{state | pid_refs: Map.put(state.pid_refs, pid, nil)}}
  end

  def handle_info({:DOWN, _ref, :process, from_pid, _reason}, state) do
    {_removed_pid, new_pid_refs} = Map.pop(state.pid_refs, from_pid)
    new_state = %{state | pid_refs: new_pid_refs}
    # Logger.debug(
    #   "METRICS:MetricClient Live _view connections = #{inspect(state)}"
    # )
    {:noreply, new_state}
  end

  def handle_info(:push_updates, current_state) do
    case Enum.empty?(current_state.pid_refs) do
      false -> send_updates(current_state)
      true -> nil
    end

    periodic_push_updates()
    {:noreply, current_state}
  end

  def handle_info({:periodic_calculation_of_points}, current_state) do
    new_state =
      case Enum.empty?(current_state.pid_refs) do
        false -> %{data: get_new_data(), pid_refs: current_state.pid_refs}
        true -> current_state
      end

    # Logger.alert("METRICS:MetricNetworkPoller  State=#{inspect(current_state)}")
    periodic_metric_aggregation()
    {:noreply, new_state}
  end

  defp get_new_data() do
    ArchEthic.Metrics.Helpers.network_collector()
  end
end
