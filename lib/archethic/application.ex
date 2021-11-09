defmodule ArchEthic.Application do
  @moduledoc false

  use Application

  alias ArchEthic.Account.Supervisor, as: AccountSupervisor

  alias ArchEthic.BeaconChain
  alias ArchEthic.BeaconChain.Supervisor, as: BeaconChainSupervisor

  alias ArchEthic.Bootstrap

  alias ArchEthic.Contracts.Supervisor, as: ContractsSupervisor

  alias ArchEthic.Crypto.Supervisor, as: CryptoSupervisor

  alias ArchEthic.DB.Supervisor, as: DBSupervisor

  alias ArchEthic.Election.Supervisor, as: ElectionSupervisor

  alias ArchEthic.Governance.Supervisor, as: GovernanceSupervisor

  alias ArchEthic.Mining.Supervisor, as: MiningSupervisor

  alias ArchEthic.Networking
  alias ArchEthic.Networking.Supervisor, as: NetworkingSupervisor

  alias ArchEthic.P2P.Supervisor, as: P2PSupervisor

  alias ArchEthic.OracleChain
  alias ArchEthic.OracleChain.Supervisor, as: OracleChainSupervisor

  alias ArchEthic.Reward
  alias ArchEthic.Reward.Supervisor, as: RewardSupervisor

  alias ArchEthic.SelfRepair
  alias ArchEthic.SelfRepair.Supervisor, as: SelfRepairSupervisor

  alias ArchEthic.SharedSecrets
  alias ArchEthic.SharedSecrets.Supervisor, as: SharedSecretsSupervisor

  alias ArchEthic.TransactionChain.Supervisor, as: TransactionChainSupervisor

  alias ArchEthic.Utils

  alias ArchEthicWeb.Endpoint, as: WebEndpoint
  alias ArchEthicWeb.Supervisor, as: WebSupervisor

  require Logger

  def start(_type, _args) do
    p2p_endpoint_conf = Application.get_env(:archethic, ArchEthic.P2P.Listener)

    port = Keyword.fetch!(p2p_endpoint_conf, :port)
    port = Networking.try_open_port(port, true)

    transport = Keyword.get(p2p_endpoint_conf, :transport, :tcp)

    children = [
      {Task.Supervisor, name: ArchEthic.TaskSupervisor},
      ArchEthic.Telemetry,
      {Registry, keys: :duplicate, name: ArchEthic.PubSubRegistry},
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
      RewardSupervisor,
      WebSupervisor,
      NetworkingSupervisor,
      {Bootstrap,
       Keyword.merge(Application.get_env(:archethic, ArchEthic.Bootstrap),
         port: port,
         transport: transport
       )}
    ]

    opts = [strategy: :rest_for_one, name: ArchEthic.Supervisor]
    Supervisor.start_link(Utils.configurable_children(children), opts)
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
