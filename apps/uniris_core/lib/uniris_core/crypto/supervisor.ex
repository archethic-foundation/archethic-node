defmodule UnirisCore.CryptoSupervisor do
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

    children =
      [
        UnirisCore.Crypto.LibSodiumPort
      ] ++
        Utils.configurable_children([
          {UnirisCore.Crypto.Keystore, [], []},
          {UnirisCore.Crypto.TransactionLoader, [renewal_interval: renewal_interval], []}
        ])

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
