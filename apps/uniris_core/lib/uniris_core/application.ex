defmodule UnirisCore.Application do
  @moduledoc false

  use Application

  alias UnirisCore.Utils

  def start(_type, _args) do
    repair_interval =
      :uniris_core
      |> Application.get_env(UnirisCore.SelfRepair)
      |> Keyword.get(:interval)

    last_sync_file =
      :uniris_core
      |> Application.get_env(UnirisCore.SelfRepair)
      |> Keyword.get(:last_sync_file)

    children =
      [
        {Task.Supervisor, name: UnirisCore.TaskSupervisor},
        {Registry, keys: :duplicate, name: UnirisCore.PubSubRegistry},
        UnirisCore.StorageSupervisor,
        UnirisCore.CryptoSupervisor,
        UnirisCore.ElectionSupervisor,
        UnirisCore.P2PSupervisor,
        UnirisCore.SharedSecretsSupervisor,
        UnirisCore.MiningSupervisor,
        UnirisCore.InterpreterSupervisor,
        UnirisCore.BeaconSupervisor
      ] ++
        Utils.configurable_children([
          {UnirisCore.SelfRepair, [interval: repair_interval, last_sync_file: last_sync_file],
           []},
          {UnirisCore.Bootstrap,
           [
             port: Application.get_env(:uniris_core, UnirisCore.P2P)[:port]
           ], []}
        ])

    opts = [strategy: :rest_for_one, name: UnirisCore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
