defmodule Uniris.MiningSupervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: Uniris.MiningRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Uniris.Mining.WorkerSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
