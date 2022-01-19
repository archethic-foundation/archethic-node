defmodule ArchEthic.Metrics.MetricSupervisor do
  @moduledoc """
  Visit dif
  """
  use Supervisor
  @supervisor_process_name __MODULE__

  # client
  def start_link(_initial_state) do
    Supervisor.start_link(__MODULE__, [], name: @supervisor_process_name)
  end

  # server/callback functions
  def init(_initial_state) do
    children = [
      ArchEthic.Metrics.MetricClient,
      ArchEthic.Metrics.MetricNetworkPoller,
      ArchEthic.Metrics.MetricNodePoller
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
