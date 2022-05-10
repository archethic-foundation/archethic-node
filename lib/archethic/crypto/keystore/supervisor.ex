defmodule Archethic.Crypto.KeystoreSupervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.Crypto.NodeKeystore.Supervisor, as: NodeKeystoreSupervisor
  alias Archethic.Crypto.SharedSecretsKeystore

  alias Archethic.Utils

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_) do
    children = [
      NodeKeystoreSupervisor,
      SharedSecretsKeystore
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :rest_for_one)
  end
end
