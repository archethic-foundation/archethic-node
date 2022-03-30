defmodule  ArchEthic.Utils.Regression.Benchmark.Helpers do
  @moduledoc """
  Helpers Methods to carry out the TPS benchmarks
  """

  require Logger

  alias ArchEthic.Crypto

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ledger
  alias ArchEthic.TransactionChain.TransactionData.NFTLedger
  alias ArchEthic.TransactionChain.TransactionData.NFTLedger.Transfer, as: NFTTransfer
  alias ArchEthic.TransactionChain.TransactionData.Ownership
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer

  alias ArchEthic.Utils.WebClient


  @faucet_seed Application.compile_env(:archethic, [ArchEthicWeb.FaucetController, :seed])


  def withdraw_uco(recipient_address, host, port) do
    recipient_address = "0000c084b09c60e3bde2d0a81df08b20d82d8b6dfc1d39bc3dfa5e41b731718f09e1"

  end

  defp create_uco_withdrawl_txn(recipient_address, host, port)do
    transaction_data = %TransactionData{
      ledger: %Ledger{uco: %UCOLedger{transfers:
        [%UCOLedger.Transfer {to: recipient_address, amount: 10_000_000_000}]}      }    }


    create_transaction(
      _type = :transfer,
      @faucet_seed,
      transaction_data,
      host,
      port,
      _curve = :ed25519)
  end

  @doc """
  Requires all neccessary parameters for building a transaction
  """
  defp create_transaction(
    transaction_type,
    transaction_seed,
    transaction_data = %TransactionData{},
    host,
    port,
    curve \\ Crypto.default_curve()) do

      #This requries to query a node host
      gensis_address_public_key, _ = Crypto.derive_keypair(transaction_seed, 0, curve)


    %Transaction{
      address: recipient_address,
      type: :transfer,
      data: transaction_data,
    }
  end

end
