defmodule ArchEthicWeb.FaucetController do
  @moduledoc false

  use ArchEthicWeb, :controller

  alias ArchEthic.TransactionChain.{
    Transaction,
    TransactionData,
    TransactionData.Ledger,
    TransactionData.UCOLedger
  }

  alias ArchEthic.Crypto

  @pool_seed Application.compile_env(:archethic, [__MODULE__, :seed])

  plug(:enabled)

  defp enabled(conn, _) do
    if Application.get_env(:archethic, __MODULE__)
       |> Keyword.get(:enabled, false) do
      conn
    else
      conn
      |> put_status(:not_found)
      |> put_view(ArchEthicWeb.ErrorView)
      |> render("404.html")
      |> halt()
    end
  end

  def index(conn, __params) do
    conn
    |> put_resp_header("cache-control", "no-cache, no-store, must-revalidate")
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("expires", "0")
    |> render("index.html", address: "", link_address: "")
  end

  def create_transfer(conn, %{"address" => address}) do
    with {:ok, recipient_address} <- Base.decode16(address, case: :mixed),
         true <- Crypto.valid_hash?(recipient_address),
         {:ok, tx_address} <- transfer(recipient_address) do
      conn
      |> put_resp_header("cache-control", "no-cache, no-store, must-revalidate")
      |> put_resp_header("pragma", "no-cache")
      |> put_resp_header("expires", "0")
      |> put_flash(:info, "Transferred successfully (click to view)")
      |> render("index.html", address: "", link_address: Base.encode16(tx_address))
    else
      {:error, _} ->
        conn
        |> put_flash(:error, "Unable to transfer")
        |> render("index.html", address: address, link_address: "")

      _ ->
        conn
        |> put_flash(:error, "Malformed address")
        |> render("index.html", address: address, link_address: "")
    end
  end

  defp transfer(
         recipient_address,
         curve \\ Crypto.default_curve()
       )
       when is_bitstring(recipient_address) do
    {gen_pub, _} = Crypto.derive_keypair(@pool_seed, 0, curve)

    pool_gen_address = Crypto.hash(gen_pub)

    with {:ok, last_address} <- ArchEthic.get_last_transaction_address(pool_gen_address),
         {:ok, last_index} <- ArchEthic.get_transaction_chain_length(last_address) do
      create_transaction(last_index, curve, recipient_address)
    else
      {:error, _} = e ->
        e
    end
  end

  defp create_transaction(transaction_index, curve, recipient_address) do
    tx =
      Transaction.new(
        :transfer,
        %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %UCOLedger.Transfer{
                  to: recipient_address,
                  amount: 10_000_000_000
                }
              ]
            }
          }
        },
        @pool_seed,
        transaction_index,
        curve
      )

    case ArchEthic.send_new_transaction(tx) do
      :ok ->
        {:ok, tx.address}

      {:error, _} = e ->
        e
    end
  end
end
