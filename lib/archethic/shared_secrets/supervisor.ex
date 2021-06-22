defmodule ArchEthic.SharedSecrets.Supervisor do
  @moduledoc false

  use Supervisor

  alias ArchEthic.SharedSecrets.MemTables.NetworkLookup
  alias ArchEthic.SharedSecrets.MemTables.OriginKeyLookup
  alias ArchEthic.SharedSecrets.MemTablesLoader

  alias ArchEthic.SharedSecrets.NodeRenewalScheduler

  alias ArchEthic.Utils

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: ArchEthic.SharedSecretSupervisor)
  end

  def init(_args) do
    optional_children = [
      NetworkLookup,
      OriginKeyLookup,
      MemTablesLoader,
      {NodeRenewalScheduler, Application.get_env(:archethic, NodeRenewalScheduler)}
    ]

    children = Utils.configurable_children(optional_children)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
