defmodule ArchEthic.Metrics.MetricSupervisor do
  @moduledoc """
  Supervisor implementation for child process :
      ArchEthic.Metrics.Poller,
      Strat-Used : one for one
  """
  use Supervisor
  alias ArchEthic.Metrics.Helpers

  def start_link(_initial_state) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_initial_state) do
    children = [
      {ArchEthic.Metrics.Poller,
       [options: [name: ArchEthic.Metrics.Poller], default_state: Helpers.poller_default_state()]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
