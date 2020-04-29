defmodule UnirisCore.SharedSecretsSupervisor do
  @moduledoc false

  alias UnirisCore.Utils

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    renewal_trigger_interval =
      :uniris_core
      |> Application.get_env(UnirisCore.SharedSecrets.NodeRenewal)
      |> Keyword.fetch!(:trigger_interval)

    children =
      [
        UnirisCore.SharedSecrets.Cache
      ] ++
        Utils.configurable_children([
          {UnirisCore.SharedSecrets.NodeRenewal, [interval: renewal_trigger_interval], []},
          {UnirisCore.SharedSecrets.TransactionLoader, [], []}
        ])

    Supervisor.init(children, strategy: :one_for_one)
  end
end
