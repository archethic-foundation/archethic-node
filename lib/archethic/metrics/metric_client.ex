defmodule ArchEthic.Metrics.MetricClient do
  @moduledoc """
  gensever
  Visit dif
  """
  use GenServer
  @process_name __MODULE__
  @default_state %{
    counter: 0
  }
  def start_link(_init_arg) do
    GenServer.start_link(__MODULE__, @default_state, name: @process_name)
  end

  def init(_state) do
    {:ok, @default_state}
  end

  def get_this_node_points() do
    ArchEthic.Metrics.MetricNodePoller.get_points()
  end

  def get_network_points() do
    ArchEthic.Metrics.MetricNetworkPoller.get_points()
  end

  def monitor() do
    GenServer.call(@process_name, :monitor)
  end

  def handle_call(:monitor, {from_pid, _ref}, state) do
    ArchEthic.Metrics.MetricNodePoller.set_flag()
    ArchEthic.Metrics.MetricNetworkPoller.set_flag()
    IO.inspect "metric_client"
    IO.inspect state
    _mref = Process.monitor(from_pid)
    {:reply, :ok, %{state | counter: state.counter + 1}}
  end

  def handle_info({:DOWN, _ref, :process, _from_pid, _reason}, state) do
    new_state = %{state | counter: state.counter - 1}
    IO.inspect "metric_client"
    IO.inspect state

    if new_state.counter == 0 do
      ArchEthic.Metrics.MetricNodePoller.unset_flag()
      ArchEthic.Metrics.MetricNetworkPoller.unset_flag()
    end
    {:noreply, new_state}
  end
end
