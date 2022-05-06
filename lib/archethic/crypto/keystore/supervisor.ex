defmodule Archethic.Crypto.KeystoreSupervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.Crypto.NodeKeystore
  alias Archethic.Crypto.SharedSecretsKeystore

  alias Archethic.Utils

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_) do
    node_keystore_impl = Application.get_env(:archethic, NodeKeystore)
    node_keystore_conf = Application.get_env(:archethic, node_keystore_impl)

    children = [
      {NodeKeystore, node_keystore_conf},
      SharedSecretsKeystore
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :rest_for_one)
  end
end
