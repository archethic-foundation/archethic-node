defmodule UnirisWeb.NodeController do
  @moduledoc false

  use UnirisWeb, :controller

  alias Uniris.Crypto
  alias Uniris.P2P
  alias Uniris.P2P.Node

  def index(conn, _params) do
    render(conn, "index.html", nodes: P2P.list_nodes())
  end

  def show(conn, _params = %{"public_key" => public_key}) do
    pub = Base.decode16!(public_key, case: :mixed)

    case P2P.get_node_info(pub) do
      {:ok, node = %Node{last_public_key: last_public_key}} ->
        node_address = Crypto.hash(last_public_key)
        %{uco: uco_balance} = Uniris.get_balance(node_address)
        render(conn, "show.html", node: node, uco_balance: uco_balance, node_address: node_address)

      _ ->
        render(conn, "show.html", node: nil, balance: 0.0)
    end
  end
end
