defmodule Archethic.Utils.Regression.Benchmark.GetFunds  do
  @moduledoc false

  require Logger

  alias Archethic.Crypto

  alias Archethic.TransactionChain.{
    Transaction,
    TransactionData,
    TransactionData.Ledger,
    TransactionData.UCOLedger
  }

  alias ArchethicWeb.TransactionSubscriber

  @pool_seed Application.compile_env(:archethic, [ArchethicWeb.FaucetController, :seed])
  alias Archethic.Utils.Regression.Benchmark.TxnGenerator

  def main()do
    # recipient_address =
    #   "receiver_seed"
    #   |> Crypto.derive_keypair(0)
    #   |> elem(0)
    #   |> Crypto.derive_address()


    # IO.inspect("", label: "recp")
    Enum.map(TxnGenerator.sender_seed(), &TxnGenerator.get_address(&1))
    |>create_transfer()
  end


  def create_transfer(address) when is_list(address) do
    Logger.error("create")

    case  transfer(address) do
      {:ok, _ } ->  Logger.info(" in ok clause  ")
        # TransactionSubscriber.register(tx_address, System.monotonic_time())
      {:error, error} ->
        Logger.info(" in else clause #{inspect error} ")
    end
  end

  def create_transfer(address) do
    with {:ok, recipient_address} <- Base.decode16(address, case: :mixed),
         true <- Crypto.valid_address?(recipient_address),
         {:ok, tx_address} <- transfer(recipient_address) do
      TransactionSubscriber.register(tx_address, System.monotonic_time())
    else
      error ->
        Logger.info(" in else clause #{inspect error} ")
    end
  end


  def transfer(
         recipient_addresses,
         curve \\ Crypto.default_curve()
       ) do
    {gen_pub, _} = Crypto.derive_keypair(@pool_seed, 0, curve)

    pool_gen_address = Crypto.derive_address(gen_pub)

    with {:ok, last_address} <-
           Archethic.get_last_transaction_address(pool_gen_address),
         {:ok, last_index} <- Archethic.get_transaction_chain_length(last_address) do
      create_transaction(last_index, curve, recipient_addresses)
    else
      {:error, _} = e ->
        e
    end
  end


  def create_transaction(transaction_index, curve, list_of_recipient_address) when is_list(list_of_recipient_address)do
    Logger.error("txn")


    transfers =
      Enum.map(list_of_recipient_address, fn address ->
        %UCOLedger.Transfer{
          to: address,
          amount: 10 * 100_000_000
        }
      end)

    tx =
      Transaction.new(
        :transfer,
        %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: transfers
            }
          }
        },
        @pool_seed,
        transaction_index,
        curve
      )

    case Archethic.send_new_transaction(tx) do
      :ok ->
        Logger.error("new")


        {:ok, tx.address}

      {:error, _} = e ->
        e
    end
  end


  def create_transaction(transaction_index, curve, recipient_address) do
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

    case Archethic.send_new_transaction(tx) do
      :ok ->
        {:ok, tx.address}

      {:error, _} = e ->
        e
    end
  end
end
