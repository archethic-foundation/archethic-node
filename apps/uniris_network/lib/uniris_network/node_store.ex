defmodule UnirisNetwork.NodeStore do
  @moduledoc false

  alias UnirisNetwork.Node

  @spec list_nodes() :: list(Node.t())
  def list_nodes() do
    :ets.select(:node_store_list, [{{:_, :"$1"}, [], [:"$1"]}])
  end

  @spec put_node(Node.t()) :: :ok
  def put_node(node = %Node{}) do
    :ets.insert(:node_store_list, {node.first_public_key, node})
    :ets.insert(:node_store_last, {node.last_public_key, node.first_public_key})
    :ok
  end

  @spec fetch_node(<<_::264>>) :: Node.t() | {:error, :node_not_exists}
  def fetch_node(<<public_key::binary-33>>) do
    case :ets.lookup(:node_store_list, public_key) do
      [{_, node}] ->
        node

      [] ->
        case :ets.lookup(:node_store_last, public_key) do
          [{_, first_key}] ->
            [{_, node}] = :ets.lookup(:node_store_list, first_key)
            node

          _ ->
            {:error, :node_not_exists}
        end
    end
  end
end
