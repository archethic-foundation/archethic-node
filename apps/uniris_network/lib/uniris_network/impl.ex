defmodule UnirisNetwork.Impl do
  @moduledoc false

  alias UnirisNetwork.Node

  @callback storage_nonce() :: binary()
  @callback set_daily_nonce(binary()) :: :ok
  @callback daily_nonce() :: binary()
  @callback origin_public_keys() :: list(UnirisCrypto.key())
  @callback list_nodes() :: list(Node.t())
  @callback add_node(Node.t()) :: :ok
  @callback node_info(UnirisCrypto.key() | :inet.ip_address()) :: Node.t()
  @callback send_message(Node.t(), term()) :: {:ok, term()}
end
