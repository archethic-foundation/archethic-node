defmodule ArchethicWeb.ExplorerController do
  @moduledoc false

  use ArchethicWeb, :controller

  alias Archethic.Crypto
  alias Archethic.TransactionChain.Transaction
  alias Archethic.OracleChain

  def index(conn, _params) do
    render(conn, "index.html", layout: {ArchethicWeb.LayoutView, "index.html"})
  end

  def search(conn, _params = %{"address" => address}) do
    with {:ok, address} <- Base.decode16(address, case: :mixed),
         true <- Crypto.valid_address?(address),
         {:ok, tx} <- Archethic.search_transaction(address) do
      previous_address = Transaction.previous_address(tx)

      render(conn, "transaction_details.html", transaction: tx, previous_address: previous_address)
    else
      _reason ->
        render(conn, "404.html")
    end
  end
end
