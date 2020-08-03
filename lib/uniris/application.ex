defmodule Uniris.Application do
  @moduledoc false

  use Application

  alias Uniris.BeaconSupervisor

  alias Uniris.CryptoSupervisor

  alias Uniris.ElectionSupervisor

  alias Uniris.InterpreterSupervisor
  alias Uniris.MiningSupervisor

  alias Uniris.P2PSupervisor

  alias Uniris.SelfRepair
  alias Uniris.SharedSecretsSupervisor
  alias Uniris.StorageSupervisor

  alias Uniris.Utils

  alias UnirisWeb.Endpoint, as: WebEndpoint
  alias UnirisWeb.Supervisor, as: WebSupervisor

  def start(_type, _args) do
    self_repair_conf = Application.get_env(:uniris, SelfRepair)
    repair_interval = Keyword.fetch!(self_repair_conf, :interval)
    last_sync_file = Keyword.fetch!(self_repair_conf, :last_sync_file)

    children =
      [
        {Task.Supervisor, name: Uniris.TaskSupervisor},
        {Registry, keys: :duplicate, name: Uniris.PubSubRegistry},
        StorageSupervisor,
        CryptoSupervisor,
        ElectionSupervisor,
        P2PSupervisor,
        SharedSecretsSupervisor,
        MiningSupervisor,
        InterpreterSupervisor,
        BeaconSupervisor,
        WebSupervisor
      ] ++
        Utils.configurable_children([
          {Uniris.SelfRepair, [interval: repair_interval, last_sync_file: last_sync_file], []},
          {Uniris.Bootstrap,
           [
             port: Application.get_env(:uniris, Uniris.P2P.Endpoint)[:port]
           ], []}
        ])

    opts = [strategy: :rest_for_one, name: Uniris.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    # Tell Phoenix to update the endpoint configuration
    # whenever the application is updated.
    WebEndpoint.config_change(changed, removed)
    :ok
  end
end
