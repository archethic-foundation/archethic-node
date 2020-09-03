defmodule Uniris.Application do
  @moduledoc false

  use Application

  alias Uniris.BeaconSupervisor
  alias Uniris.Bootstrap

  alias Uniris.CryptoSupervisor

  alias Uniris.ElectionSupervisor

  alias Uniris.InterpreterSupervisor

  alias Uniris.MiningSupervisor

  alias Uniris.P2P.Endpoint, as: P2PEndpoint
  alias Uniris.P2PSupervisor

  alias Uniris.SelfRepair
  alias Uniris.SharedSecretsRenewal
  alias Uniris.StorageSupervisor

  alias Uniris.Utils

  alias UnirisWeb.Endpoint, as: WebEndpoint
  alias UnirisWeb.Supervisor, as: WebSupervisor

  def start(_type, _args) do
    repair_interval = Application.get_env(:uniris, SelfRepair)[:interval]
    last_sync_file = Application.get_env(:uniris, SelfRepair)[:last_sync_file]

    node_renewal_interval = Application.get_env(:uniris, SharedSecretsRenewal)[:interval]

    node_renewal_trigger_offset =
      Application.get_env(:uniris, SharedSecretsRenewal)[:trigger_offset]

    children =
      [
        {Task.Supervisor, name: Uniris.TaskSupervisor},
        {Registry, keys: :duplicate, name: Uniris.PubSubRegistry},
        StorageSupervisor,
        CryptoSupervisor,
        ElectionSupervisor,
        P2PSupervisor,
        MiningSupervisor,
        InterpreterSupervisor,
        BeaconSupervisor,
        WebSupervisor
      ] ++
        Utils.configurable_children([
          {SharedSecretsRenewal,
           [interval: node_renewal_interval, trigger_offset: node_renewal_trigger_offset], []},
          {SelfRepair, [interval: repair_interval, last_sync_file: last_sync_file], []},
          {Bootstrap,
           [
             port: Application.get_env(:uniris, P2PEndpoint)[:port]
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
