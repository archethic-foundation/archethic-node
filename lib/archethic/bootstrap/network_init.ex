defmodule ArchEthic.Bootstrap.NetworkInit do
  @moduledoc """
  Set up the network by initialize genesis information (i.e storage nonce, coinbase transactions)

  Those functions are only executed by the first node bootstrapping on the network
  """

  alias ArchEthic.Bootstrap

  alias ArchEthic.BeaconChain.ReplicationAttestation

  alias ArchEthic.Crypto

  alias ArchEthic.Election

  alias ArchEthic.Mining

  alias ArchEthic.PubSub

  alias ArchEthic.Replication

  alias ArchEthic.SharedSecrets

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.CrossValidationStamp
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ledger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger.Transfer
  alias ArchEthic.TransactionChain.TransactionData.Ownership

  alias ArchEthic.TransactionChain.TransactionSummary

  require Logger

  @genesis_seed Application.compile_env(:archethic, [__MODULE__, :genesis_seed])

  @genesis_origin_public_keys Application.compile_env!(
                                :archethic,
                                [__MODULE__, :genesis_origin_public_keys]
                              )

  defp get_genesis_pools do
    Application.get_env(:archethic, __MODULE__) |> Keyword.get(:genesis_pools, [])
  end

  @doc """
  Initialize the storage nonce and load it into the keystore
  """
  @spec create_storage_nonce() :: :ok
  def create_storage_nonce do
    Logger.info("Create storage nonce")
    storage_nonce_seed = :crypto.strong_rand_bytes(32)
    {_, pv} = Crypto.generate_deterministic_keypair(storage_nonce_seed)
    Crypto.decrypt_and_set_storage_nonce(Crypto.ec_encrypt(pv, Crypto.last_node_public_key()))
  end

  @doc """
  Create the first node shared secret transaction
  """
  @spec init_node_shared_secrets_chain() :: :ok
  def init_node_shared_secrets_chain do
    Logger.info("Create first node shared secret transaction")
    secret_key = :crypto.strong_rand_bytes(32)
    daily_nonce_seed = :crypto.strong_rand_bytes(32)

    tx =
      SharedSecrets.new_node_shared_secrets_transaction(
        [Crypto.first_node_public_key()],
        daily_nonce_seed,
        secret_key
      )

    tx
    |> self_validation()
    |> self_replication()
  end

  @doc """
  Create the first origin shared secret transaction
  """
  @spec init_software_origin_shared_secrets_chain() :: :ok
  def init_software_origin_shared_secrets_chain do
    Logger.info("Create first software origin shared secret transaction")

    origin_seed = :crypto.strong_rand_bytes(32)
    secret_key = :crypto.strong_rand_bytes(32)
    signing_seed = SharedSecrets.get_origin_family_seed(:software)

    # Default keypair generation creates software public key
    {origin_public_key, origin_private_key} = Crypto.generate_deterministic_keypair(origin_seed)

    encrypted_origin_private_key = Crypto.aes_encrypt(origin_private_key, secret_key)

    Transaction.new(
      :origin_shared_secrets,
      %TransactionData{
        code: """
          condition inherit: [
            # We need to ensure the type stays consistent
            # So we can apply specific rules during the transaction validation
            type: origin_shared_secrets
          ]
        """,
        content: <<origin_public_key::binary>>,
        ownerships: [
          Ownership.new(encrypted_origin_private_key, secret_key, @genesis_origin_public_keys)
        ]
      },
      signing_seed,
      0
    )
    |> self_validation()
    |> self_replication()
  end

  @doc """
  Initializes the genesis wallets for the UCO distribution
  """
  @spec init_genesis_wallets() :: :ok
  def init_genesis_wallets do
    network_pool_address = SharedSecrets.get_network_pool_address()
    Logger.info("Create UCO distribution genesis transaction")

    tx =
      network_pool_address
      |> genesis_transfers()
      |> create_genesis_transaction()

    genesis_transfers_amount =
      tx
      |> Transaction.get_movements()
      |> Enum.reduce(0, &(&2 + &1.amount))

    tx
    |> self_validation([
      %UnspentOutput{
        from: Bootstrap.genesis_unspent_output_address(),
        amount: genesis_transfers_amount,
        type: :UCO
      }
    ])
    |> self_replication()
  end

  defp create_genesis_transaction(genesis_transfers) do
    Transaction.new(
      :transfer,
      %TransactionData{
        ledger: %Ledger{
          uco: %UCOLedger{
            transfers: genesis_transfers
          }
        }
      },
      @genesis_seed,
      0
    )
  end

  defp genesis_transfers(network_pool_address) do
    get_genesis_pools()
    |> Enum.map(&%Transfer{to: &1.address, amount: &1.amount})
    |> Enum.concat([%Transfer{to: network_pool_address, amount: 146_000_000_000_000_000}])
  end

  @spec self_validation(Transaction.t(), list(UnspentOutput.t())) :: Transaction.t()
  def self_validation(tx = %Transaction{}, unspent_outputs \\ []) do
    operations =
      %LedgerOperations{
        fee: Mining.get_transaction_fee(tx, 0.07),
        transaction_movements: Transaction.get_movements(tx)
      }
      |> LedgerOperations.from_transaction(tx)
      |> LedgerOperations.consume_inputs(tx.address, unspent_outputs)

    validation_stamp =
      %ValidationStamp{
        timestamp: DateTime.utc_now(),
        proof_of_work: Crypto.first_node_public_key(),
        proof_of_election:
          Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
        proof_of_integrity: tx |> Transaction.serialize() |> Crypto.hash(),
        ledger_operations: operations
      }
      |> ValidationStamp.sign()

    cross_validation_stamp = CrossValidationStamp.sign(%CrossValidationStamp{}, validation_stamp)

    %{
      tx
      | validation_stamp: validation_stamp,
        cross_validation_stamps: [cross_validation_stamp]
    }
  end

  @spec self_replication(Transaction.t()) :: :ok
  def self_replication(tx = %Transaction{}) do
    :ok = Replication.validate_and_store_transaction_chain(tx)

    tx_summary = TransactionSummary.from_transaction(tx)

    attestation = %ReplicationAttestation{
      transaction_summary: tx_summary,
      confirmations: [
        {0, Crypto.sign_with_first_node_key(TransactionSummary.serialize(tx_summary))}
      ]
    }

    PubSub.notify_replication_attestation(attestation)
  end
end
