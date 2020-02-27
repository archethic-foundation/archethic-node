defmodule UnirisNetwork.Impl do
  @moduledoc false

  alias UnirisNetwork.Node

  @callback storage_nonce() :: binary()
  @callback set_daily_nonce(binary()) :: :ok
  @callback daily_nonce() :: binary()
  @callback origin_public_keys() :: list(binary())
  @callback list_nodes() :: list(Node.t())
  @callback add_node(Node.t()) :: :ok
  @callback node_info(binary()) :: Node.t()
  @callback node_public_key_by_ip(:inet.ip_address()) :: binary()
  @callback send_message(Node.t(), term()) :: {:ok, term()}
end
