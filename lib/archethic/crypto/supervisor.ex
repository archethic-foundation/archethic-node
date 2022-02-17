defmodule ArchEthic.Crypto.Supervisor do
  @moduledoc false
  use Supervisor

  alias ArchEthic.Crypto.Ed25519.LibSodiumPort
  alias ArchEthic.Crypto.KeystoreSupervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: ArchEthic.CryptoSupervisor)
  end

  def init(_args) do
    children = [LibSodiumPort, KeystoreSupervisor]
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
