defmodule UnirisCore.SharedSecretsSupervisor do
  @moduledoc false

  alias UnirisCore.Utils
  alias UnirisCore.SharedSecrets.NodeRenewal
  alias UnirisCore.SharedSecrets.TransactionLoader
  alias UnirisCore.SharedSecrets.Cache

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    interval = Application.get_env(:uniris_core, NodeRenewal)[:interval]
    trigger_offset = Application.get_env(:uniris_core, NodeRenewal)[:trigger_offset]

    children =
      [
        Cache
      ] ++
        Utils.configurable_children([
          {NodeRenewal, [interval: interval, trigger_offset: trigger_offset], []},
          {TransactionLoader, [], []}
        ])

    Supervisor.init(children, strategy: :one_for_one)
  end
end
