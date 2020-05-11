defmodule UnirisWeb.ExplorerController do
  use UnirisWeb, :controller

  alias UnirisCore.Transaction
  alias UnirisCore.Storage
  alias UnirisCore.Crypto

  def index(conn, _params) do
    render(conn, "index.html")
  end

  def search(conn, params = %{"address" => address}) do
    with {:ok, address} <- Base.decode16(address),
         {:ok, tx} <- UnirisCore.search_transaction(address) do
      previous_address = Crypto.hash(tx.previous_public_key)
      render(conn, "transaction_details.html", transaction: tx, previous_address: previous_address)
    else
      reason ->
        render(conn, "404.html")
    end
  end
end
