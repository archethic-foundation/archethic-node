defmodule ArchEthic.Metrics.Poller do
  @moduledoc """
  Provides Telemetry of the network and Maneges
  """
  alias ArchEthic.Metrics.Helpers
  require Logger
  use GenServer

  @spec start_link(any) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(_state) do
    GenServer.start_link(__MODULE__, Helpers.poller_default_state(), name: __MODULE__)
  end

  @spec init(any) :: {:ok, any}
  def init(initial_state) do
    periodic_metric_aggregation()
    {:ok, initial_state}
  end

  @spec periodic_metric_aggregation :: reference
  def periodic_metric_aggregation() do
    Process.send_after(self(), {:periodic_calculation_of_points}, 10_000)
  end

  @spec monitor :: any
  def monitor() do
    GenServer.call(__MODULE__, :monitor)
  end

  def handle_call(:monitor, {pid, __tag}, state) do
    {:reply, :ok, Helpers.register_process(pid, state)}
  end

  def handle_info({:DOWN, _ref, :process, from_pid, _reason}, state) do
    {:noreply, Helpers.deregister_process(from_pid, state)}
  end

  def handle_info({:periodic_calculation_of_points}, current_state) do
    new_state = Helpers.process_new_state(current_state)
    periodic_metric_aggregation()
    {:noreply, new_state}
  end
end
