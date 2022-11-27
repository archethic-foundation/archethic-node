defmodule Archethic.SelfRepair.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.SelfRepair.{Notifier, Scheduler}
  alias Archethic.Utils

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      {Scheduler, Application.get_env(:archethic, Scheduler)},
      {DynamicSupervisor, strategy: :one_for_one, name: Notifier.RepairSupervisor},
      {Registry, name: Notifier.RepairRegistry, keys: :unique, partitions: 1}
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :one_for_one)
  end
end
