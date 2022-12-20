defmodule ArchethicWeb.FaucetController do
  @moduledoc false

  use ArchethicWeb, :controller

  alias Archethic.Crypto

  alias Archethic.TransactionChain.{
    Transaction,
    TransactionData,
    TransactionData.Ledger,
    TransactionData.UCOLedger
  }

  alias ArchethicWeb.{TransactionSubscriber, FaucetRateLimiter}

  @pool_seed Application.compile_env(:archethic, [__MODULE__, :seed])
  @faucet_rate_limit_expiry Application.compile_env(:archethic, :faucet_rate_limit_expiry)

  plug(:enabled)

  defp enabled(conn, _) do
    if Application.get_env(:archethic, __MODULE__) |> Keyword.get(:enabled, false) or
         Application.get_env(:archethic, __MODULE__) |> Keyword.get(:test_enabled, false) do
      conn
    else
      conn
      |> put_status(:not_found)
      |> put_view(ArchethicWeb.ErrorView)
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
    with address <- String.trim(address),
         {:ok, recipient_address} <- Base.decode16(address, case: :mixed),
         true <- Crypto.valid_address?(recipient_address),
         %{blocked?: false} <- FaucetRateLimiter.get_address_block_status(recipient_address),
         {:ok, tx} <- prepare_transaction(recipient_address),
         {:ok, tx_address} <- send_tx(tx, recipient_address) do
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

      %{blocked?: true, blocked_since: blocked_since} ->
        now = System.monotonic_time()
        blocked_elapsed_time = System.convert_time_unit(now - blocked_since, :native, :second)
        blocked_elapsed_diff = div(@faucet_rate_limit_expiry, 1000) - blocked_elapsed_time

        conn
        |> put_flash(
          :error,
          "Blocked address as you exceeded usage limit of UCO temporarily. Try after #{Archethic.Utils.seconds_to_human_readable(blocked_elapsed_diff)}"
        )
        |> render("index.html", address: address, link_address: "")

      _ ->
        conn
        |> put_flash(:error, "Malformed address")
        |> render("index.html", address: address, link_address: "")
    end
  end

  @spec prepare_transaction(binary()) :: {:ok, Transaction.t()} | {:error, any()}
  defp prepare_transaction(recipient_address) do
    pool_gen_address =
      @pool_seed
      |> Crypto.derive_keypair(0)
      |> elem(0)
      |> Crypto.derive_address()

    with {:ok, last_address} <- Archethic.get_last_transaction_address(pool_gen_address),
         {:ok, last_index} <- Archethic.get_transaction_chain_length(last_address) do
      {:ok, Transaction.new(:transfer, get_tx_data(recipient_address), @pool_seed, last_index)}
    else
      {:error, e} ->
        e
    end
  end

  # for compile time values
  @unit_uco 100_000_000
  @max_uco 100
  @uco_limit @max_uco * @unit_uco
  defp get_tx_data(recipient_address) do
    %TransactionData{
      ledger: %Ledger{
        uco: %UCOLedger{
          transfers: [
            %UCOLedger.Transfer{
              to: recipient_address,
              amount: @uco_limit
            }
          ]
        }
      }
    }
  end

  defp send_tx(tx = %Transaction{address: tx_address}, recipient_address) do
    TransactionSubscriber.register(tx_address, System.monotonic_time())

    case Archethic.send_new_transaction(tx) do
      :ok ->
        receive do
          {:new_transaction, ^tx_address} ->
            FaucetRateLimiter.register(recipient_address, System.monotonic_time())
            {:ok, tx_address}
        after
          # requires dynamic timeout
          5000 ->
            {:error, :network_issue}
        end

      {:error, _} = e ->
        e
    end
  end
end
