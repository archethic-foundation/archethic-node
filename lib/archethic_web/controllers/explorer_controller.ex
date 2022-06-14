defmodule ArchethicWeb.ExplorerController do
  @moduledoc false

  use ArchethicWeb, :controller

  alias Archethic.OracleChain
  alias Archethic.Crypto
  alias Archethic.TransactionChain.Transaction

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

  def chain(conn, _params = %{"address" => address, "last" => "on"}) do
    with {:ok, addr} <- Base.decode16(address, case: :mixed),
         true <- Crypto.valid_address?(addr),
         {:ok, %Transaction{address: last_address}} <- Archethic.get_last_transaction(addr),
         {:ok, chain} <- Archethic.get_transaction_chain(last_address),
         {:ok, %{uco: uco_balance}} <- Archethic.get_balance(addr),
         uco_price <- DateTime.utc_now() |> OracleChain.get_uco_price() do
      render(conn, "chain.html",
        transaction_chain: List.flatten(chain),
        chain_size: Enum.count(chain),
        address: addr,
        uco_balance: uco_balance,
        last_checked?: true,
        uco_price: uco_price
      )
    else
      :error ->
        render(conn, "chain.html",
          transaction_chain: [],
          chain_size: 0,
          address: "",
          last_checked?: true,
          error: :invalid_address,
          uco_balance: 0,
          uco_price: [eur: 0.05, usd: 0.07]
        )

      {:error, _} ->
        render(conn, "chain.html",
          transaction_chain: [],
          chain_size: 0,
          address: "",
          last_checked?: true,
          error: :network_issue,
          uco_balance: 0,
          uco_price: [eur: 0.05, usd: 0.07]
        )

      false ->
        render(conn, "chain.html",
          transaction_chain: [],
          chain_size: 0,
          address: "",
          last_checked?: true,
          error: :invalid_address,
          uco_balance: 0,
          uco_price: [eur: 0.05, usd: 0.07]
        )

      _ ->
        render(conn, "chain.html",
          transaction_chain: [],
          chain_size: 0,
          address: Base.decode16!(address, case: :mixed),
          last_checked?: true,
          uco_balance: 0,
          uco_price: [eur: 0.05, usd: 0.07]
        )
    end
  end

  def chain(conn, _params = %{"address" => address}) do
    with {:ok, addr} <- Base.decode16(address, case: :mixed),
         true <- Crypto.valid_address?(addr),
         {:ok, chain} <- Archethic.get_transaction_chain(addr),
         {:ok, %{uco: uco_balance}} <- Archethic.get_balance(addr),
         uco_price <- DateTime.utc_now() |> OracleChain.get_uco_price() do
      render(conn, "chain.html",
        transaction_chain: List.flatten(chain),
        address: addr,
        chain_size: Enum.count(chain),
        uco_balance: uco_balance,
        last_checked?: false,
        uco_price: uco_price
      )
    else
      :error ->
        render(conn, "chain.html",
          transaction_chain: [],
          address: "",
          chain_size: 0,
          uco_balance: 0,
          last_checked?: false,
          error: :invalid_address,
          uco_price: [eur: 0.05, usd: 0.07]
        )

      false ->
        render(conn, "chain.html",
          transaction_chain: [],
          address: "",
          chain_size: 0,
          uco_balance: 0,
          last_checked?: false,
          error: :invalid_address,
          uco_price: [eur: 0.05, usd: 0.07]
        )

      {:error, _} ->
        render(conn, "chain.html",
          transaction_chain: [],
          address: "",
          chain_size: 0,
          uco_balance: 0,
          last_checked?: false,
          error: :network_issue,
          uco_price: [eur: 0.05, usd: 0.07]
        )
    end
  end

  def chain(conn, _params) do
    render(conn, "chain.html",
      transaction_chain: [],
      address: "",
      chain_size: 0,
      last_checked?: false,
      uco_balance: 0,
      uco_price: [eur: 0.05, usd: 0.07]
    )
  end
end
