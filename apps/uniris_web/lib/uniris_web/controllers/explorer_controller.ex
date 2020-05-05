defmodule UnirisWeb.ExplorerController do
  use UnirisWeb, :controller

  alias UnirisCore.Transaction
  alias UnirisCore.Storage

  def index(conn, _params) do
    render(conn, "index.html")
  end

  def search(conn, params = %{"address" => address}) do
    with {:ok, address} <- Base.decode16(address),
         {:ok, tx} <- UnirisCore.search_transaction(address) do
      render(conn, "transaction_details.html", transaction: tx)
    else
      reason ->
        render(conn, "404.html")
    end
  end
end
