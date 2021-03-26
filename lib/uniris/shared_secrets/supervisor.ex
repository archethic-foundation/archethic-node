defmodule Uniris.SharedSecrets.Supervisor do
  @moduledoc false

  use Supervisor

  alias Uniris.SharedSecrets.MemTables.NetworkLookup
  alias Uniris.SharedSecrets.MemTables.OriginKeyLookup
  alias Uniris.SharedSecrets.MemTablesLoader

  alias Uniris.SharedSecrets.NodeRenewalScheduler

  alias Uniris.Utils

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: Uniris.SharedSecretSupervisor)
  end

  def init(_args) do
    optional_children = [
      NetworkLookup,
      OriginKeyLookup,
      MemTablesLoader,
      {NodeRenewalScheduler, Application.get_env(:uniris, NodeRenewalScheduler)}
    ]

    children = Utils.configurable_children(optional_children)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
