defmodule ArchEthic.Metrics.PollerTest do
  @moduledoc """
  Provides Telemetry of the network and Maneges
  """
  require Logger
  use GenServer

  @default_state %{
    pid_refs: %{},
    data: ArchEthic.Metrics.Helpers.get_client_metric_default_value()
  }

  def start_link(_state) do
    GenServer.start_link(__MODULE__, @default_state, name: __MODULE__)
  end

  def init(initial_state) do
    periodic_metric_aggregation()
    {:ok, initial_state}
  end

  def periodic_metric_aggregation() do
    Process.send_after(self(), {:periodic_calculation_of_points}, 10_000)
  end

  def send_updates(%{data: data, pid_refs: pid_refs}) do
    pid_refs
    |> Task.async_stream(fn {pid_k, _pid_v} -> send(pid_k, {:update_data, data}) end)
    |> Stream.run()
  end

  def monitor() do
    GenServer.call(__MODULE__, :monitor)
  end

  def handle_call(:monitor, {pid, __tag}, state) do
    new_state = %{state | pid_refs: Map.put(state.pid_refs, pid, nil)}
    send_updates(new_state)
    _mref = Process.monitor(pid)
    {:reply, :ok, new_state}
  end

  def handle_info({:DOWN, _ref, :process, from_pid, _reason}, state) do
    {_removed_pid, new_pid_refs} = Map.pop(state.pid_refs, from_pid)
    new_state = %{state | pid_refs: new_pid_refs}
    {:noreply, new_state}
  end

  def handle_info({:periodic_calculation_of_points}, current_state) do
    new_state =
      case Enum.empty?(current_state.pid_refs) do
        false ->
          send_updates(current_state)
          %{data: get_new_data(), pid_refs: current_state.pid_refs}

        true ->
          current_state
      end

    periodic_metric_aggregation()
    {:noreply, new_state}
  end

  defp get_new_data() do
    ArchEthic.Metrics.Helpers.network_collector()
  end
end
