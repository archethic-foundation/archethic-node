defmodule Uniris.CryptoSupervisor do
  @moduledoc false
  use Supervisor

  alias Uniris.Crypto.Keystore
  alias Uniris.Crypto.LibSodiumPort
  alias Uniris.Crypto.TransactionLoader

  alias Uniris.SharedSecrets.NodeRenewal
  alias Uniris.Utils

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    renewal_interval = Application.get_env(:uniris, NodeRenewal)[:interval]

    children =
      [LibSodiumPort] ++
        Utils.configurable_children([
          {Keystore, [], []},
          {TransactionLoader, [renewal_interval: renewal_interval], []}
        ])

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
