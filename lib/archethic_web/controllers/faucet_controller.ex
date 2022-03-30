defmodule ArchEthicWeb.FaucetController do
  @moduledoc false

  use ArchEthicWeb, :controller

  alias ArchEthic.Crypto

  alias ArchEthic.TransactionChain.{
    Transaction,
    TransactionData,
    TransactionData.Ledger,
    TransactionData.UCOLedger
  }

  alias ArchEthicWeb.TransactionSubscriber
  alias ArchEthicWeb.FaucetRateLimiter

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
    FaucetRateLimiter.register(address, System.monotonic_time())

    with {:ok, recipient_address} <- Base.decode16(address, case: :mixed),
         true <- Crypto.valid_address?(recipient_address),
         %{archived?: false} <- FaucetRateLimiter.get_address_archive_status(address),
         {:ok, tx_address} <- transfer(recipient_address) do
      TransactionSubscriber.register(tx_address, System.monotonic_time())

      conn
      |> put_resp_header("cache-control", "no-cache, no-store, must-revalidate")
      |> put_resp_header("pragma", "no-cache")
      |> put_resp_header("expires", "0")
      |> put_flash(:info, "Transaction submitted (click to see it)")
      |> render("index.html", address: "", link_address: Base.encode16(tx_address))
    else
      {:error, _} ->
        conn
        |> put_flash(:error, "Unable to send the transaction")
        |> render("index.html", address: address, link_address: "")

      %{archived?: true, archived_since: archived_since} ->
        now = System.monotonic_time()
        archived_elapsed_time = System.convert_time_unit(now - archived_since, :native, :second)

        conn
        |> put_flash(
          :error,
          "Archived address, Try after #{ArchEthic.Utils.seconds_to_hh_mm_ss(archived_elapsed_time)}"
        )
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

    pool_gen_address = Crypto.derive_address(gen_pub)

    with {:ok, last_address} <-
           ArchEthic.get_last_transaction_address(pool_gen_address),
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
