defmodule Archethic.Metrics.MetricSupervisor do
  @moduledoc false
  use Supervisor

  alias Archethic.Utils

  def start_link(_initial_state) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_initial_state) do
    children =
      Utils.configurable_children([
        Archethic.Metrics.Poller
      ])

    Supervisor.init(children, strategy: :one_for_one)
  end
end
