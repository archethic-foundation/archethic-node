defmodule Archethic.SelfRepair.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.SelfRepair.Scheduler
  alias Archethic.SelfRepair.NetworkChainView
  alias Archethic.Utils

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      {Scheduler, Application.get_env(:archethic, Scheduler)},
      {DynamicSupervisor, strategy: :one_for_one, name: Archethic.SelfRepair.NotifierSupervisor},
      {Registry,
       name: Archethic.SelfRepair.RepairRegistry,
       keys: :unique,
       partitions: System.schedulers_online()},
      NetworkChainView
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :one_for_one)
  end
end
