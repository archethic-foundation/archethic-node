defmodule UnirisP2P.Impl do
  @moduledoc false

  alias UnirisP2P.Node
  alias UnirisCrypto, as: Crypto

  @callback connect_node(Node.t()) :: :ok
  @callback list_nodes() :: list(Node.t())
  @callback add_node(Node.t()) :: :ok
  @callback node_info(Crypto.key() | :inet.ip_address()) ::
              {:ok, Node.t()} | {:error, :not_found}

  @callback send_message(
              Crypto.key() | Node.t() | :inet.ip_address(),
              message :: any()
            ) :: :ok

  @callback list_seeds() :: list(Node.t())
  @callback update_seeds(list(Node.t())) :: :ok
end
