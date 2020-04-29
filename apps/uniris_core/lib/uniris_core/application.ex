defmodule UnirisCore.Application do
  @moduledoc false

  use Application

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
      ] ++ configurable_children()

    opts = [strategy: :rest_for_one, name: UnirisCore.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp configurable_children() do
    [
      configure(UnirisCore.Bootstrap,
        port: Application.get_env(:uniris_core, UnirisCore.P2P)[:port],
        seeds_file: Application.get_env(:uniris_core, UnirisCore.Bootstrap)[:seeds_file]
      ),
      configure(UnirisCore.SelfRepair,
        interval: Application.get_env(:uniris_core, UnirisCore.SelfRepair)[:interval]
      )
    ]
    |> List.flatten()
  end

  defp configure(process, args, opts \\ []) do
    if should_start?(process) do
      Supervisor.child_spec({process, args}, opts)
    else
      []
    end
  end

  defp should_start?(process) do
    :uniris_core
    |> Application.get_env(process, enabled: true)
    |> Keyword.fetch!(:enabled)
  end
end
