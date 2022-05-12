defmodule Archethic.Crypto.NodeKeystore.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.Crypto.NodeKeystore
  alias Archethic.Crypto.NodeKeystore.Origin

  alias Archethic.Utils

  def start_link(arg \\ []) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_) do
    node_keystore_impl = Application.get_env(:archethic, NodeKeystore, NodeKeystore.SoftwareImpl)
    node_keystore_conf = Application.get_env(:archethic, node_keystore_impl)

    children = [
      {NodeKeystore, node_keystore_conf},
      Origin
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :one_for_one)
  end
end
