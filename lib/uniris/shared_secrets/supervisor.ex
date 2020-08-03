defmodule Uniris.SharedSecretsSupervisor do
  @moduledoc false

  alias Uniris.SharedSecrets.Cache
  alias Uniris.SharedSecrets.NodeRenewal
  alias Uniris.SharedSecrets.TransactionLoader
  alias Uniris.Utils

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    interval = Application.get_env(:uniris, NodeRenewal)[:interval]
    trigger_offset = Application.get_env(:uniris, NodeRenewal)[:trigger_offset]

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
