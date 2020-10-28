defmodule Uniris.Mining.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: Uniris.MiningSupervisor)
  end

  def init(_opts) do
    children = [
      {Registry, name: Uniris.Mining.WorkflowRegistry, keys: :unique},
      {DynamicSupervisor, strategy: :one_for_one, name: Uniris.Mining.WorkerSupervisor}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
