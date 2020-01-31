defmodule UnirisNetwork.Impl do
  @moduledoc false

  alias UnirisNetwork.Node
  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp

  @callback storage_nonce() :: binary()
  @callback daily_nonce() :: binary()
  @callback origin_public_keys() :: list(binary())
  @callback list_nodes() :: list(Node.t())
  @callback node_info(binary()) :: {:ok, Node.t()} | {:error, :node_not_exists}
end
