defmodule ArchEthic.Metrics.MetricClient do
  @moduledoc """
  A genserver Implementation
  Provides abstraction for querying node_live_metrics and
  network_live_metrics though get
  """
  require Logger
  use GenServer
  def start_link(_init_arg) do
    GenServer.start_link(__MODULE__ , %{ counter: 0 } , name: __MODULE__)
  end

  def init(initial_state) do
    Logger.info("Metic-Client Started")
    {:ok, initial_state}
  end

  def subscribe_to_node_updates() do
    ArchEthic.Metrics.MetricNodePoller.get_points()
  end

  def subscribe_to_network_updates() do
    ArchEthic.Metrics.MetricNetworkPoller.get_points()
  end

  def monitor() do
    GenServer.call(__MODULE__, :monitor)
  end

  def handle_call(:monitor, {from_pid, _ref}, state) do
    ArchEthic.Metrics.MetricNodePoller.set_flag()
    ArchEthic.Metrics.MetricNetworkPoller.set_flag()
    _mref = Process.monitor(from_pid)

    Logger.debug(
      "METRICS : MetricClient Live _view connections = #{inspect(state.counter + 1)}||||"
    )

    {:reply, :ok, %{state | counter: state.counter + 1}}
  end

  def handle_info({:DOWN, _ref, :process, _from_pid, _reason}, state) do
    new_state = %{state | counter: state.counter - 1}

    if new_state.counter == 0 do
      ArchEthic.Metrics.MetricNodePoller.unset_flag()
      ArchEthic.Metrics.MetricNetworkPoller.unset_flag()
      Logger.debug("METRICS:MetricClient Polling stopped ")
    end

    Logger.debug(
      "METRICS:MetricClient Live _view connections = #{inspect(new_state.counter)} ||||"
    )

    {:noreply, new_state}
  end
end
