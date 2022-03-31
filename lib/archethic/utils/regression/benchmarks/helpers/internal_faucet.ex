defmodule ArchEthic.Utils.Regression.Benchmarks.Helpers.InternalFaucet do
  @moduledoc """
  Executes  UCO withrawl internally to the Tx-blockchain.
  """

  alias ArchEthicWeb.TransactionSubscriber
  alias ArchEthic.Crypto

  alias ArchEthic.TransactionChain.{
    Transaction,
    TransactionData,
    TransactionData.Ledger,
    TransactionData.UCOLedger
  }

  alias ArchEthicWeb.TransactionSubscriber

  @pool_seed Application.compile_env(:archethic, [ArchEthicWeb.FaucetController, :seed])

  def main(recipient_address) do
    initiate_transfer(recipient_address)
  end

  defp initiate_transfer(wallet_address) do
    # if Application.get_env(:archethic, ArchEthicWeb.FaucetController)
    #    |> Keyword.get(:enabled, false) do
    create_transfer(wallet_address)
    # else
    #   {:error, :faucet_disabled}
    # end
  end

  def create_transfer(address) do
    with {:ok, recipient_address} <- Base.decode16(address, case: :mixed),
         true <- Crypto.valid_address?(recipient_address),
         {:ok, tx_address} <- transfer(recipient_address) do
      TransactionSubscriber.register(tx_address, System.monotonic_time())
      {:ok, :transferred}
    else
      _ -> {:error, :failure}
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
