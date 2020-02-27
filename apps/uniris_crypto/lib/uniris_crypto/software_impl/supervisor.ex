defmodule UnirisCrypto.SoftwareImpl.Supervisor do
  @moduledoc false
  use Supervisor

  alias UnirisCrypto.SoftwareImpl.LibSodiumPort, as: Ed25519Port

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children = [
      Ed25519Port
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
