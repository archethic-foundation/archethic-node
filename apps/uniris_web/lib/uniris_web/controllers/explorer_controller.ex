defmodule UnirisWeb.ExplorerController do
  use UnirisWeb, :controller

  alias UnirisCore.Crypto
  alias UnirisCore.Transaction

  def index(conn, _params) do
    render(conn, "index.html")
  end

  def search(conn, _params = %{"address" => address}) do
    with {:ok, address} <- Base.decode16(address),
         {:ok, tx} <- UnirisCore.search_transaction(address) do
      previous_address = Crypto.hash(tx.previous_public_key)

      render(conn, "transaction_details.html", transaction: tx, previous_address: previous_address)
    else
      _reason ->
        render(conn, "404.html")
    end
  end

  def chain(conn, _params = %{"address" => address, "last" => "on"}) do
    bin_address = Base.decode16!(address)

    case UnirisCore.get_last_transaction(bin_address) do
      {:ok, %Transaction{address: last_address}} ->
        chain = UnirisCore.get_transaction_chain(last_address)
        inputs = UnirisCore.get_transaction_inputs(bin_address)

        render(conn, "chain.html",
          transaction_chain: chain,
          address: address,
          balance: Enum.reduce(inputs, 0.0, &(&2 + &1.amount))
        )

      _ ->
        render(conn, "chain.html", transaction_chain: [], address: address)
    end
  end

  def chain(conn, _params = %{"address" => address}) do
    bin_address = Base.decode16!(address)
    chain = UnirisCore.get_transaction_chain(bin_address)
    inputs = UnirisCore.get_transaction_inputs(bin_address)

    render(conn, "chain.html",
      transaction_chain: chain,
      address: address,
      balance: Enum.reduce(inputs, 0.0, &(&2 + &1.amount))
    )
  end

  def chain(conn, _params) do
    render(conn, "chain.html", transaction_chain: [], address: "")
  end
end
