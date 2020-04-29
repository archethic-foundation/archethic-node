defmodule UnirisCore.P2P.NodeViewSupervisor do
  @moduledoc false

  use Supervisor

  alias UnirisCore.Utils

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    renewal_interval =
      :uniris_core
      |> Application.get_env(UnirisCore.SharedSecrets.NodeRenewal)
      |> Keyword.fetch!(:interval)

    Supervisor.init(
      [
        {Registry, keys: :unique, name: UnirisCore.P2P.NodeRegistry},
        {DynamicSupervisor, name: UnirisCore.P2P.NodeSupervisor, strategy: :one_for_one}
      ] ++
        Utils.configurable_children([
          {UnirisCore.P2P.TransactionLoader, [renewal_interval: renewal_interval], []}
        ]),
      strategy: :rest_for_one
    )
  end
end
