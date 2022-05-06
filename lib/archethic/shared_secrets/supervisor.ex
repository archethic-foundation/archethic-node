defmodule Archethic.SharedSecrets.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.SharedSecrets.MemTables.NetworkLookup
  alias Archethic.SharedSecrets.MemTables.OriginKeyLookup
  alias Archethic.SharedSecrets.MemTablesLoader

  alias Archethic.SharedSecrets.NodeRenewalScheduler

  alias Archethic.Utils

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: Archethic.SharedSecretSupervisor)
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
