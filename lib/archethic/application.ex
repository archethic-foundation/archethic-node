defmodule Archethic.Application do
  @moduledoc false

  use Application

  alias Archethic.Account.Supervisor, as: AccountSupervisor

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.Supervisor, as: BeaconChainSupervisor

  alias Archethic.Bootstrap

  alias Archethic.Contracts.Supervisor, as: ContractsSupervisor

  alias Archethic.Crypto.Supervisor, as: CryptoSupervisor

  alias Archethic.DB.Supervisor, as: DBSupervisor

  alias Archethic.Election.Supervisor, as: ElectionSupervisor

  alias Archethic.Governance.Supervisor, as: GovernanceSupervisor

  alias Archethic.Mining.Supervisor, as: MiningSupervisor

  alias Archethic.Networking
  alias Archethic.Networking.Supervisor, as: NetworkingSupervisor

  alias Archethic.P2P.Supervisor, as: P2PSupervisor
  alias Archethic.P2P.ListenerSupervisor

  alias Archethic.OracleChain
  alias Archethic.OracleChain.Supervisor, as: OracleChainSupervisor

  alias Archethic.Replication.Supervisor, as: ReplicationSupervisor

  alias Archethic.Reward
  alias Archethic.Reward.Supervisor, as: RewardSupervisor

  alias Archethic.SelfRepair
  alias Archethic.SelfRepair.Supervisor, as: SelfRepairSupervisor

  alias Archethic.SharedSecrets
  alias Archethic.SharedSecrets.Supervisor, as: SharedSecretsSupervisor

  alias Archethic.TransactionChain.Supervisor, as: TransactionChainSupervisor

  alias Archethic.Utils

  alias ArchethicWeb.Endpoint, as: WebEndpoint
  alias ArchethicWeb.Supervisor, as: WebSupervisor

  alias Archethic.Metrics.MetricSupervisor, as: MetricSupervisor

  alias Mix.Tasks.Archethic.Migrate

  require Logger

  def start(_type, _args) do
    # First start the migration process synchronously
    Application.spec(:archethic, :vsn) |> Migrate.run(false)

    # Then start the Archethic Supervisor
    p2p_endpoint_conf = Application.get_env(:archethic, Archethic.P2P.Listener)
    web_endpoint_conf = Application.get_env(:archethic, ArchethicWeb.Endpoint)

    port = Keyword.fetch!(p2p_endpoint_conf, :port)
    {:ok, port} = Networking.try_open_port(port, true)
    try_open_port(Keyword.get(web_endpoint_conf, :http))
    try_open_port(Keyword.get(web_endpoint_conf, :https))

    http = Keyword.fetch!(web_endpoint_conf, :http)
    http_port = Keyword.fetch!(http, :port)

    transport = Keyword.get(p2p_endpoint_conf, :transport, :tcp)

    children = [
      {Task.Supervisor, name: Archethic.TaskSupervisor},
      Archethic.Telemetry,
      {Registry, keys: :duplicate, name: Archethic.PubSubRegistry},
      DBSupervisor,
      TransactionChainSupervisor,
      CryptoSupervisor,
      ElectionSupervisor,
      P2PSupervisor,
      MiningSupervisor,
      BeaconChainSupervisor,
      SharedSecretsSupervisor,
      ReplicationSupervisor,
      RewardSupervisor,
      AccountSupervisor,
      GovernanceSupervisor,
      SelfRepairSupervisor,
      OracleChainSupervisor,
      ContractsSupervisor,
      {ListenerSupervisor, port: port},
      WebSupervisor,
      NetworkingSupervisor,
      {Bootstrap,
       Keyword.merge(Application.get_env(:archethic, Archethic.Bootstrap),
         port: port,
         http_port: http_port,
         transport: transport
       )},
      MetricSupervisor,

      # a registry used in Utils to ensure a function is executed at most once concurrently
      {Registry, keys: :unique, name: Archethic.RunExclusiveRegistry},
      {Registry, keys: :unique, name: Archethic.Utils.JobCacheRegistry}
    ]

    opts = [strategy: :rest_for_one, name: Archethic.Supervisor]
    Supervisor.start_link(Utils.configurable_children(children), opts)
  end

  def start_phase(:migrate, :normal, _options) do
    Application.spec(:archethic, :vsn) |> Migrate.run(false)
  end

  defp try_open_port(nil), do: :ok

  defp try_open_port(conf) do
    port = Keyword.get(conf, :port)
    Networking.try_open_port(port, false)
  end

  def config_change(changed, _new, removed) do
    # Tell Phoenix to update the endpoint configuration
    # whenever the application is updated.
    WebEndpoint.config_change(changed, removed)

    # Update the configuration of process which depends on configuration
    SharedSecrets.config_change(changed)
    SelfRepair.config_change(changed)
    OracleChain.config_change(changed)
    Reward.config_change(changed)
    BeaconChain.config_change(changed)
    :ok
  end
end
