defmodule Archethic.SelfRepair.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.SelfRepair.NetworkChainWorker, as: ChainWorker
  alias Archethic.SelfRepair.NetworkView
  alias Archethic.SelfRepair.Scheduler
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
      NetworkView,

      # spawn worker to resync network chains
      {Registry, keys: :unique, name: Archethic.SelfRepair.WorkerRegistry},
      Supervisor.child_spec({ChainWorker, :node}, id: ChainWorker.Node),
      Supervisor.child_spec({ChainWorker, :reward}, id: ChainWorker.Reward),
      Supervisor.child_spec({ChainWorker, :oracle}, id: ChainWorker.Oracle),
      Supervisor.child_spec({ChainWorker, :origin}, id: ChainWorker.Origin),
      Supervisor.child_spec({ChainWorker, :node_shared_secrets}, id: ChainWorker.NodeSharedSecrets)
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :one_for_one)
  end
end
