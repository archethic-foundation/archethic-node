defmodule ArchEthic.Utils.Regression.Benchmarks.Helpers.TPSHelper do
  @moduledoc """
  Helpers Methods to carry out the TPS benchmarks
  """
  alias ArchEthic.Utils.Regression.Playbook

  alias ArchEthic.TransactionChain.{
    Transaction,
    TransactionData,
    TransactionData.Ledger,
    TransactionData.UCOLedger
  }

  alias ArchEthic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer
  alias ArchEthic.Crypto

  @faucet_seed Application.compile_env(:archethic, [ArchEthicWeb.FaucetController, :seed])

  # =========================================================================
  # Implementation via internal Methods
  # =========================================================================
  def random_seed(), do: Integer.to_string(Enum.random(1..1_000_000_000_000))

  def get_genesis_address(seed), do: derive_keys(seed) |> derive_genesis_addess()

  def derive_keys(seed), do: Crypto.derive_keypair(seed, 0, Crypto.default_curve())

  def derive_genesis_addess({pbKey, _privKey}), do: Crypto.derive_address(pbKey)

  def allocate_funds(recipient_address) do
    # {:ok, recipient_address} = valid_recipient_address(recipient_address)

    pool_genesis_address = get_genesis_address(@faucet_seed)

    with {:ok, last_address} <-
           ArchEthic.get_last_transaction_address(pool_genesis_address),
         {:ok, last_index} <- ArchEthic.get_transaction_chain_length(last_address) do
      create_transaction(last_index, Crypto.default_curve(), recipient_address)
    else
      {:error, _} = e ->
        e
    end
  end

  # defp valid_recipient_address(recipient_address) do
  #   with {:ok, recipient_address} <- Base.decode16(recipient_address, case: :mixed),
  #        true <- Crypto.valid_address?(recipient_address) do
  #     {:ok, recipient_address}
  #   else
  #     {:error, _} -> {:error, nil}
  #   end
  # end

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
        @faucet_seed,
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

  def get_transaction(sender_seed, recipient_address) when is_bitstring(recipient_address) do
    # {:ok, recipient_address} = valid_recipient_address(recipient_address)
    sender_genesis_address = get_genesis_address(sender_seed)

    with {:ok, last_address} <-
           ArchEthic.get_last_transaction_address(sender_genesis_address),
         {:ok, last_index} <- ArchEthic.get_transaction_chain_length(last_address) do
      build_transaction(sender_seed, last_index, recipient_address)
    else
      {:error, _} = e ->
        e
    end
  end

  def build_transaction(sender_seed, txn_index, recipient_address) do
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

  # =========================================================================
  # Implementation via public api/endpoints
  # pending : validation :ok and replication
  # =========================================================================
  # get dummy uco from the host
  def withdraw_uco_via_host(recipient_address, host, port, amount) do
    Playbook.send_funds_to(recipient_address, host, port, amount)
  end

  # deploys a transaction
  def send_transaction({{sender_seed, transaction_data}, host, port}) do
    # pending
    Playbook.send_transaction(
      sender_seed,
      :transfer,
      transaction_data,
      host,
      port,
      Crypto.default_curve()
    )
  end

  # creates a sender and reciever address and seed for benchmarking function
  # this function is executed before each benchmark function call
  # whatever parameter it returns is used for input in benchmark function
  def before_each_scenario_instance({host, port}) do
    # Random seed generation
    # System.unqiuew give unquire value for each runtime
    sender_seed = Integer.to_string(Enum.random(1..1_000_000_000_000))

    {sender_public_key, _private_key} =
      Crypto.derive_keypair(sender_seed, 0, Crypto.default_curve())

    sender_address = Crypto.derive_address(sender_public_key)
    withdraw_uco_via_host(sender_address, host, port, 10)

    recipient_seed = Integer.to_string(Enum.random(1..1_000_000_000_000))

    {recipient_public_key, _private_key} =
      Crypto.derive_keypair(recipient_seed, 0, Crypto.default_curve())

    recipient_address = Crypto.derive_address(recipient_public_key)

    # send dummy uco to recipient
    transaction_data = get_transaction_data(recipient_address)
    {{sender_seed, transaction_data}, host, port}
  end

  def get_transaction_data(recipient_address) do
    %TransactionData{
      ledger: %Ledger{
        uco: %UCOLedger{
          transfers: [
            %UCOTransfer{
              to: recipient_address,
              amount: 10_000
            }
          ]
        }
      }
    }
  end
end
