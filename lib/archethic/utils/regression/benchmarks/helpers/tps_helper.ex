defmodule ArchEthic.Utils.Regression.Benchmarks.Helpers.TPSHelper do
  @moduledoc """
  Povides methods to help with benchmarking TPS.
  """
  # Modules req
  alias ArchEthic.Crypto

  alias ArchEthic.TransactionChain.{
    Transaction,
    TransactionData,
    TransactionData.Ledger,
    TransactionData.UCOLedger
  }

  alias ArchEthicWeb.TransactionSubscriber

  # module variables
  @pool_seed Application.compile_env(:archethic, [ArchEthicWeb.FaucetController, :seed])

  def random_seed(), do: Integer.to_string(System.unique_integer([:monotonic]))

  @spec faucet_enabled?() :: {:ok, boolean()}
  def faucet_enabled?(),
    do: {
      :ok,
      # System.get_env("ARCHETHIC_NETWORK_TYPE") == "testnet"}
      true
    }

  def get_curve(), do: Crypto.default_curve()

  # hash of genesis public key
  def acquire_genesis_address({genesis_pbKey, _privKey}), do: derive_address(genesis_pbKey)
  def acquire_genesis_address(genesis_pbKey), do: derive_address(genesis_pbKey)

  # hash of public key
  def derive_address(pbKey), do: Crypto.derive_address(pbKey)

  def derive_keys(seed, index \\ 0), do: Crypto.derive_keypair(seed, index, get_curve())

  def allocate_funds(recipient_address) do
    with {:ok, true} <- faucet_enabled?(),
         {:ok, recipient_address} <- Base.decode16(recipient_address, case: :mixed),
         true <- Crypto.valid_address?(recipient_address),
         {:ok, tx_address} <- transfer_dummy_uco(recipient_address) do
      TransactionSubscriber.register(tx_address, System.monotonic_time())
      {:ok, tx_address}
    else
      _ -> {:error, :raise}
    end
  end

  def transfer_dummy_uco(recipient_address) when is_bitstring(recipient_address) do
    pool_gen_address = derive_keys(@pool_seed) |> acquire_genesis_address()

    with {:ok, last_address} <-
           ArchEthic.get_last_transaction_address(pool_gen_address),
         {:ok, last_index} <- ArchEthic.get_transaction_chain_length(last_address) do
      faucet_create_transaction(last_index, get_curve(), recipient_address)
    else
      {:error, _} = e ->
        e
    end
  end

  defp faucet_create_transaction(transaction_index, curve, recipient_address) do
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

  # tested works fines till here
  def valid_transfer(recipient_address) do
    with {:ok, true} <- faucet_enabled?(),
         true <- Crypto.valid_address?(recipient_address) do
      {:ok, recipient_address}
    else
      _ -> {:error, nil}
    end
  end

  def transfer(sender_seed, recipient_address) do
    {:ok, recipient_address} = valid_transfer(recipient_address)
    sender_genesis_address = sender_seed |> derive_keys() |> acquire_genesis_address()

    with {:ok, last_address} <-
           ArchEthic.get_last_transaction_address(sender_genesis_address),
         {:ok, last_index} <- ArchEthic.get_transaction_chain_length(last_address) do
      create_transaction(sender_seed, last_index, recipient_address)
    else
      {:error, _} = e ->
        e
    end
  end

  def create_transaction(sender_seed, txn_index, recipient_address) do
    Transaction.new(
      :transfer,
      %TransactionData{
        ledger: %Ledger{
          uco: %UCOLedger{
            transfers: [
              %UCOLedger.Transfer{
                to: recipient_address,
                amount: 1_000_000
              }
            ]
          }
        }
      },
      sender_seed,
      txn_index
    )
  end

  def deploy_txn(txn) do
    case ArchEthic.send_new_transaction(txn) do
      :ok ->
        {:ok}

      {:error, _} = e ->
        e
    end
  end
end
