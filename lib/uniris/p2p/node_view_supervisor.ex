defmodule Uniris.P2P.NodeViewSupervisor do
  @moduledoc false

  use Supervisor

  alias Uniris.SharedSecrets.NodeRenewal
  alias Uniris.Utils

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    renewal_interval = Application.get_env(:uniris, NodeRenewal)[:interval]

    Supervisor.init(
      [
        {Registry, keys: :unique, name: Uniris.P2P.NodeRegistry},
        {DynamicSupervisor, name: Uniris.P2P.NodeSupervisor, strategy: :one_for_one}
      ] ++
        Utils.configurable_children([
          {Uniris.P2P.TransactionLoader, [renewal_interval: renewal_interval], []}
        ]),
      strategy: :rest_for_one
    )
  end
end
