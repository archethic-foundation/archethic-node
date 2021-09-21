defmodule ArchEthicWeb.FaucetController do
  @moduledoc false

  alias ArchEthic.TransactionChain.{
    Transaction,
    TransactionData,
    TransactionData.Ledger,
    TransactionData.UCOLedger
  }

  alias ArchEthic.Crypto

  use ArchEthicWeb, :controller

  def index(conn, __params) do
    conn
    |> put_resp_header("cache-control", "no-cache, no-store, must-revalidate")
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("expires", "0")
    |> render("index.html", address: "")
  end

  def create_transfer(conn, %{"address" => address}) do
    case transfer(address, Crypto.default_curve()) do
      :ok ->
        conn
        |> put_flash(:info, "Transferred successfully")
        |> redirect(to: "/faucet")

      {:error, _} ->
        conn
        |> put_flash(:error, "Unable to transfer")
        |> render("index.html", address: address)
    end
  end

  defp transfer(
         address,
         curve
       )
       when is_bitstring(address) do
    gen_seed = Application.get_env(:archethic, __MODULE__)[:seed]

    {gen_pub, _} = Crypto.derive_keypair(gen_seed, 0, curve)

    pool_gen_address = Crypto.hash(gen_pub)

    last_address =
      case ArchEthic.get_last_transaction(pool_gen_address) do
        {:ok, transaction} ->
          %ArchEthic.TransactionChain.Transaction{address: last_address} = transaction
          last_address

        {:error, :transaction_not_exists} ->
          pool_gen_address
      end

    last_index = ArchEthic.get_transaction_chain_length(last_address)

    Transaction.new(
      :transfer,
      %TransactionData{
        ledger: %Ledger{
          uco: %UCOLedger{
            transfers: [
              %UCOLedger.Transfer{
                to: Base.decode16!(address, case: :mixed),
                amount: 100.0
              }
            ]
          }
        }
      },
      gen_seed,
      last_index,
      curve
    )
    |> ArchEthic.send_new_transaction()
  end
end
