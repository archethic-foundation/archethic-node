defmodule UnirisCrypto.SoftwareImpl.Supervisor do
  @moduledoc false
  use Supervisor

  alias UnirisCrypto.SoftwareImpl.LibSodiumPort, as: Ed25519Port
  alias UnirisCrypto.SoftwareImpl.Keystore

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children = [
      Ed25519Port,
      {Keystore,
       [
         origin_keypair: Application.get_env(:uniris_crypto, :origin_keypair),
         seed: Application.get_env(:uniris_crypto, :node_seed)
       ]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
