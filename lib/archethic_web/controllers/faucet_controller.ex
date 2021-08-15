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
    render(conn, "index.html", address: "")
  end

  def create_transfer(conn, %{"address" => address}) do
    case transfer(address, :secp256r1) do
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

  def transfer(
        address,
        curve \\ Application.get_env(:archethic, ArchEthic.Crypto)[:default_curve]
      )
      when is_bitstring(address) do
    gen_seed =
      System.get_env(
        "ARCHETHIC_TESTNET_GENESIS_SEED",
        "testnet"
      )

    {gen_pub, _} = Crypto.derive_keypair(gen_seed, 0, :secp256r1)

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

    {prev_pub, prev_priv} = Crypto.derive_keypair(gen_seed, last_index, curve)

    {next_pub, _} = Crypto.derive_keypair(gen_seed, last_index + 1, curve)

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
      prev_priv,
      prev_pub,
      next_pub
    )
    |> ArchEthic.send_new_transaction()
  end
end

#   def send(address) when is_bitstring(address) do
#     seed = "testnet"

#     {pub, _} = Crypto.derive_keypair(seed, 0, :secp256r1)

#     pool_gen_address = Crypto.hash(pub)

#     last_address =
#       case ArchEthic.get_last_transaction(pool_gen_address) do
#         {:ok, transaction} ->
#           %ArchEthic.TransactionChain.Transaction{address: last_address} = transaction
#           last_address

#         {:error, :transaction_not_exists} ->
#           pool_gen_address
#       end

#     last_index = ArchEthic.get_transaction_chain_length(last_address)

#     Transaction.new(
#       :transfer,
#       %TransactionData{
#         ledger: %Ledger{
#           uco: %UCOLedger{
#             transfers: [
#               %UCOLedger.Transfer{
#                 to: Base.decode16!(address, case: :mixed),
#                 amount: 100.0
#               }
#             ]
#           }
#         }
#       },
#       seed,
#       last_index
#     )
#     |> ArchEthic.send_new_transaction()
#   end
# end
