defmodule ArchEthicWeb.NodeController do
  @moduledoc false

  use ArchEthicWeb, :controller

  alias ArchEthic
  alias ArchEthic.Crypto
  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node

  def index(conn, _params) do
    render(conn, "index.html", nodes: P2P.list_nodes())
  end

  def show(conn, _params = %{"public_key" => public_key}) do
    with {:ok, pub} <- Base.decode16(public_key, case: :mixed),
         true <- Crypto.valid_public_key?(pub),
         {:ok, node = %Node{last_public_key: last_public_key, reward_address: reward_address}} <-
           P2P.get_node_info(pub) do
      node_address = Crypto.hash(last_public_key)

      render(conn, "show.html",
        node: node,
        node_address: node_address,
        reward_address: reward_address
      )
    else
      {:error, :not_found} ->
        render(conn, "show.html", node: nil)

      _ ->
        render(conn, "show.html",
          node: nil,
          mining_rewards: 0.0,
          reward_balance: 0.0,
          error: :invalid_public_key
        )
    end
  end
end
