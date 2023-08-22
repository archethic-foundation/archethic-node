defmodule Archethic.Bootstrap.NetworkInit do
  @moduledoc """
  Set up the network by initialize genesis information (i.e storage nonce, coinbase transactions)

  Those functions are only executed by the first node bootstrapping on the network
  """

  alias Archethic.Bootstrap

  alias Archethic.BeaconChain.ReplicationAttestation

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.Mining

  alias Archethic.PubSub

  alias Archethic.Replication

  alias Archethic.SharedSecrets

  alias Archethic.Reward

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer

  alias Archethic.TransactionChain.TransactionSummary

  require Logger

  @genesis_seed Application.compile_env(:archethic, [__MODULE__, :genesis_seed])

  @genesis_origin_public_keys Application.compile_env!(
                                :archethic,
                                [__MODULE__, :genesis_origin_public_keys]
                              )

  @genesis_network_pool_amount Application.compile_env!(
                                 :archethic,
                                 [__MODULE__, :genesis_network_pool_amount]
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
        secret_key,
        0
      )

    tx
    |> self_validation()
    |> self_replication()
  end

  @doc """
  Create the first origin shared secret transaction
  """
  @spec init_software_origin_chain() :: :ok
  def init_software_origin_chain do
    Logger.info("Create first software origin shared secret transaction")

    signing_seed = SharedSecrets.get_origin_family_seed(:software)

    [genesis_origin_public_key | _rest] = @genesis_origin_public_keys

    origin_cert =
      "3044022002596a4b72bc8204e331d37c98a2a6765d5ca886585d70ff0c2b60774d0489e2022028c556e3520b4ea814faa4fbf80760fd7fa56f68f531aa91561280805cd5764a"
      |> Base.decode16!(case: :mixed)

    Transaction.new(
      :origin,
      %TransactionData{
        code: """
          condition inherit: [
            # We need to ensure the type stays consistent
            # So we can apply specific rules during the transaction validation
            type: origin,
            content: true
          ]
        """,
        content:
          <<genesis_origin_public_key::binary, byte_size(origin_cert)::16, origin_cert::binary>>
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
    Logger.info("Create UCO distribution genesis transaction")

    tx =
      get_genesis_pools()
      |> Enum.map(&%Transfer{to: &1.address, amount: &1.amount})
      |> create_genesis_transaction()

    genesis_transfers_amount =
      tx
      |> Transaction.get_movements()
      |> Enum.reduce(0, &(&2 + &1.amount))

    timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    tx
    |> self_validation([
      %UnspentOutput{
        from: Bootstrap.genesis_unspent_output_address(),
        amount: genesis_transfers_amount,
        type: :UCO,
        timestamp: timestamp
      }
    ])
    |> self_replication()
  end

  @spec init_network_reward_pool() :: :ok
  def init_network_reward_pool() do
    Logger.info("Create mining reward pool")

    Reward.new_rewards_mint(@genesis_network_pool_amount, 0)
    |> self_validation()
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

  @spec self_validation(Transaction.t(), list(UnspentOutput.t())) :: Transaction.t()
  def self_validation(tx = %Transaction{}, unspent_outputs \\ []) do
    timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    operations =
      %LedgerOperations{
        fee: Mining.get_transaction_fee(tx, 0.07, timestamp),
        transaction_movements: Transaction.get_movements(tx),
        tokens_to_mint: LedgerOperations.get_utxos_from_transaction(tx, timestamp)
      }
      |> LedgerOperations.consume_inputs(
        tx.address,
        unspent_outputs,
        timestamp
      )
      |> elem(1)

    validation_stamp =
      %ValidationStamp{
        protocol_version: 1,
        timestamp: timestamp,
        proof_of_work: Crypto.origin_node_public_key(),
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
    :ok = Replication.sync_transaction_chain(tx)

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
