defmodule ArchEthic.Utils.Regression.Benchmark.Helpers do
  @moduledoc """
  Helpers Methods to carry out the TPS benchmarks
  """

  require Logger

  alias ArchEthic.Crypto

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ledger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger

  @faucet_seed Application.compile_env(:archethic, [ArchEthicWeb.FaucetController, :seed])

  def withdraw_uco() do
    recipient_address = "0000c084b09c60e3bde2d0a81df08b20d82d8b6dfc1d39bc3dfa5e41b731718f09e1"
    create_uco_withdrawl_txn(recipient_address)
  end

  defp create_uco_withdrawl_txn(recipient_address) do
    curve = Crypto.default_curve()
    # This requries to query a node host
    # derive public key for genesis address
    {genesis_address_public_key, _} = Crypto.derive_keypair(@faucet_seed, 0, curve)

    #
    pool_genesis_address = Crypto.derive_address(genesis_address_public_key)

    with {:ok, last_address} <-
           ArchEthic.get_last_transaction_address(pool_genesis_address),
         {:ok, chain_length} <- ArchEthic.get_transaction_chain_length(last_address) do
      create_transaction(chain_length, curve, recipient_address)
    else
      {:error, _} = e ->
        e
    end
  end

  @doc """
  Requires all neccessary parameters for building a transaction
  """
  def create_transaction(
        index,
        curve \\ Crypto.default_curve(),
        recipient_address
      ) do
    transaction_seed = @faucet_seed

    transaction_data = %TransactionData{
      ledger: %Ledger{
        uco: %UCOLedger{
          transfers: [%UCOLedger.Transfer{to: recipient_address, amount: 10_000_000_000}]
        }
      }
    }

    {previous_public_key, previous_private_key} =
      Crypto.derive_keypair(transaction_seed, index, curve)

    {next_public_key, _} = Crypto.derive_keypair(transaction_seed, index + 1, curve)

    txn =
      %Transaction{
        address: Crypto.derive_address(next_public_key),
        type: :transfer,
        data: transaction_data,
        previous_public_key: previous_public_key
      }
      |> Transaction.previous_sign_transaction(previous_private_key)
      |> Transaction.origin_sign_transaction()

    case ArchEthic.send_new_transaction(txn) do
      :ok ->
        {:ok, txn.address}

      {:error, _} = e ->
        e
    end
  end
end
