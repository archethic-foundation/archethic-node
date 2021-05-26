defmodule Uniris.Crypto.KeystoreSupervisor do
  @moduledoc false

  use Supervisor

  alias Uniris.Crypto.NodeKeystore
  alias Uniris.Crypto.SharedSecretsKeystore

  alias Uniris.Utils

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_) do
    node_keystore_impl = Utils.impl(NodeKeystore)

    children = [
      {NodeKeystore, Application.get_env(:uniris, node_keystore_impl)},
      SharedSecretsKeystore
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :rest_for_one)
  end
end
