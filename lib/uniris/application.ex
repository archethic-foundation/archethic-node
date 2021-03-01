defmodule Uniris.Application do
  @moduledoc false

  use Application

  alias Uniris.Account.Supervisor, as: AccountSupervisor
  alias Uniris.BeaconChain.Supervisor, as: BeaconChainSupervisor
  alias Uniris.Bootstrap
  alias Uniris.Contracts.Supervisor, as: ContractsSupervisor
  alias Uniris.Crypto.Supervisor, as: CryptoSupervisor
  alias Uniris.DB.Supervisor, as: DBSupervisor
  alias Uniris.Election.Supervisor, as: ElectionSupervisor
  alias Uniris.Governance.Supervisor, as: GovernanceSupervisor
  alias Uniris.Mining.Supervisor, as: MiningSupervisor

  alias Uniris.Networking

  alias Uniris.P2P.Supervisor, as: P2PSupervisor

  alias Uniris.OracleChain.Supervisor, as: OracleChainSupervisor

  alias Uniris.SelfRepair.Supervisor, as: SelfRepairSupervisor
  alias Uniris.SharedSecrets.Supervisor, as: SharedSecretsSupervisor
  alias Uniris.TransactionChain.Supervisor, as: TransactionChainSupervisor

  alias Uniris.Utils

  alias UnirisWeb.Endpoint, as: WebEndpoint
  alias UnirisWeb.Supervisor, as: WebSupervisor

  require Logger

  def start(_type, _args) do
    p2p_endpoint_conf = Application.get_env(:uniris, Uniris.P2P.Endpoint)

    port = Keyword.fetch!(p2p_endpoint_conf, :port)
    Logger.info("Try to open the port #{port}")
    port = Networking.try_open_port(port, true)

    transport = Keyword.get(p2p_endpoint_conf, :transport, :tcp)

    children = [
      Uniris.Telemetry,
      {Registry, keys: :duplicate, name: Uniris.PubSubRegistry},
      DBSupervisor,
      TransactionChainSupervisor,
      CryptoSupervisor,
      ElectionSupervisor,
      {P2PSupervisor, port: port},
      MiningSupervisor,
      ContractsSupervisor,
      BeaconChainSupervisor,
      SharedSecretsSupervisor,
      AccountSupervisor,
      GovernanceSupervisor,
      SelfRepairSupervisor,
      OracleChainSupervisor,
      WebSupervisor,
      {Bootstrap, port: port, transport: transport},
      {Task.Supervisor, name: Uniris.TaskSupervisor}
    ]

    opts = [strategy: :rest_for_one, name: Uniris.Supervisor]
    Supervisor.start_link(Utils.configurable_children(children), opts)
  end

  def config_change(changed, _new, removed) do
    # Tell Phoenix to update the endpoint configuration
    # whenever the application is updated.
    WebEndpoint.config_change(changed, removed)
    :ok
  end
end
