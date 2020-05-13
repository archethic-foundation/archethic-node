defmodule UnirisCore.Application do
  @moduledoc false

  use Application

  alias UnirisCore.Utils

  def start(_type, _args) do
    children =
      [
        {Task.Supervisor, name: UnirisCore.TaskSupervisor},
        {Registry, keys: :duplicate, name: UnirisCore.PubSubRegistry},
        UnirisCore.StorageSupervisor,
        UnirisCore.CryptoSupervisor,
        UnirisCore.ElectionSupervisor,
        UnirisCore.SharedSecretsSupervisor,
        UnirisCore.P2PSupervisor,
        UnirisCore.MiningSupervisor,
        UnirisCore.InterpreterSupervisor,
        UnirisCore.BeaconSupervisor
      ] ++
        Utils.configurable_children([
          {UnirisCore.Bootstrap,
           [
             port: Application.get_env(:uniris_core, UnirisCore.P2P)[:port],
             seeds_file: Application.get_env(:uniris_core, UnirisCore.Bootstrap)[:seeds_file]
           ], []},
          {
            UnirisCore.SelfRepair,
            [interval: Application.get_env(:uniris_core, UnirisCore.SelfRepair)[:interval]],
            []
          }
        ])

    opts = [strategy: :rest_for_one, name: UnirisCore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
