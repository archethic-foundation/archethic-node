defmodule ArchEthic.Metrics.MetricSupervisor do
  @moduledoc """
  Supervisor implementation for child process :
      ArchEthic.Metrics.MetricClient,
      ArchEthic.Metrics.MetricNetworkPoller,
      ArchEthic.Metrics.MetricNodePoller
      Strat-Used : one for one
  """
  use Supervisor

  def start_link(_initial_state) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_initial_state) do
    children = [
      ArchEthic.Metrics.MetricClient,
      ArchEthic.Metrics.MetricNetworkPoller,
      ArchEthic.Metrics.MetricNodePoller
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
