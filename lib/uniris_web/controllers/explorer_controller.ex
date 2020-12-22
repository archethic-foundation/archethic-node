defmodule UnirisWeb.ExplorerController do
  @moduledoc false

  use UnirisWeb, :controller

  alias Uniris.TransactionChain.Transaction

  def index(conn, _params) do
    render(conn, "index.html", layout: {UnirisWeb.LayoutView, "index.html"})
  end

  def search(conn, _params = %{"address" => address}) do
    with {:ok, address} <- Base.decode16(address, case: :mixed),
         {:ok, tx} <- Uniris.search_transaction(address) do
      previous_address = Transaction.previous_address(tx)

      render(conn, "transaction_details.html", transaction: tx, previous_address: previous_address)
    else
      _reason ->
        render(conn, "404.html")
    end
  end

  def chain(conn, _params = %{"address" => address, "last" => "on"}) do
    bin_address = Base.decode16!(address, case: :mixed)

    case Uniris.get_last_transaction(bin_address) do
      {:ok, %Transaction{address: last_address}} ->
        chain = Uniris.get_transaction_chain(last_address)
        %{uco: uco_balance} = Uniris.get_balance(bin_address)

        render(conn, "chain.html",
          transaction_chain: chain,
          chain_size: Enum.count(chain),
          address: bin_address,
          uco_balance: uco_balance,
          last_checked?: true
        )

      _ ->
        render(conn, "chain.html",
          transaction_chain: [],
          chain_size: 0,
          address: bin_address,
          last_checked?: true
        )
    end
  end

  def chain(conn, _params = %{"address" => address}) do
    bin_address = Base.decode16!(address, case: :mixed)
    chain = Uniris.get_transaction_chain(bin_address)
    %{uco: uco_balance} = Uniris.get_balance(bin_address)

    render(conn, "chain.html",
      transaction_chain: chain,
      address: bin_address,
      chain_size: Enum.count(chain),
      uco_balance: uco_balance,
      last_checked?: false
    )
  end

  def chain(conn, _params) do
    render(conn, "chain.html",
      transaction_chain: [],
      address: "",
      chain_size: 0,
      last_checked?: false
    )
  end
end
