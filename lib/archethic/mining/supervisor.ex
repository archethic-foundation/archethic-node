defmodule Archethic.Mining.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: Archethic.MiningSupervisor)
  end

  def init(_opts) do
    children = [
      {Registry,
       name: Archethic.Mining.WorkflowRegistry,
       keys: :unique,
       partitions: System.schedulers_online()},
      {DynamicSupervisor, strategy: :one_for_one, name: Archethic.Mining.WorkerSupervisor}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
