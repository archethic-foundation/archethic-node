defmodule UnirisWeb.NodeController do
  @moduledoc false

  use UnirisWeb, :controller

  alias Uniris.Crypto
  alias Uniris.P2P

  def index(conn, _params) do
    render(conn, "index.html", nodes: P2P.list_nodes())
  end

  def show(conn, _params = %{"public_key" => public_key}) do
    pub = Base.decode16!(public_key, case: :mixed)

    case P2P.get_node_info(pub) do
      {:ok, node} ->
        node_address = Crypto.hash(pub)
        %{uco: uco_balance} = Uniris.get_balance(node_address)
        render(conn, "show.html", node: node, uco_balance: uco_balance)

      _ ->
        render(conn, "show.html", node: nil, balance: 0.0)
    end
  end
end
