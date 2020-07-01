defmodule UnirisCore.Bootstrap.NetworkInit do
  @moduledoc false

  alias UnirisCore.Crypto
  alias UnirisCore.SharedSecrets
  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.TransactionData.Ledger
  alias UnirisCore.TransactionData.Ledger.Transfer
  alias UnirisCore.TransactionData.UCOLedger
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.Transaction.CrossValidationStamp
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias UnirisCore.Beacon
  alias UnirisCore.P2P.Node
  alias UnirisCore.Mining.Context

  require Logger

  @doc """
  Initialize the storage nonce and load it into the keystore
  """
  @spec create_storage_nonce() :: :ok
  def create_storage_nonce() do
    Logger.info("Create storage nonce")
    storage_nonce_seed = :crypto.strong_rand_bytes(32)
    {_, pv} = Crypto.generate_deterministic_keypair(storage_nonce_seed)
    Crypto.decrypt_and_set_storage_nonce(Crypto.ec_encrypt(pv, Crypto.node_public_key()))
  end

  @doc """
  Create the first node shared secret transaction
  """
  @spec init_node_shared_secrets_chain(network_pool_seed :: binary()) :: :ok
  def init_node_shared_secrets_chain(network_pool_seed) do
    Logger.info("Create first node shared secret transaction")
    aes_key = :crypto.strong_rand_bytes(32)
    encrypted_aes_key = Crypto.ec_encrypt(aes_key, Crypto.node_public_key())

    :crypto.strong_rand_bytes(32)
    |> Crypto.aes_encrypt(aes_key)
    |> Crypto.decrypt_and_set_node_shared_secrets_transaction_seed(encrypted_aes_key)

    network_pool_seed
    |> Crypto.aes_encrypt(aes_key)
    |> Crypto.decrypt_and_set_node_shared_secrets_network_pool_seed(encrypted_aes_key)

    daily_nonce_seed = :crypto.strong_rand_bytes(32)

    tx =
      SharedSecrets.new_node_shared_secrets_transaction(
        [Crypto.node_public_key(0)],
        daily_nonce_seed,
        aes_key
      )

    tx
    |> self_validation!()
    |> self_replication()

    Node.authorize(Crypto.node_public_key(0), tx.timestamp)

    Crypto.decrypt_and_set_daily_nonce_seed(
      Crypto.aes_encrypt(daily_nonce_seed, aes_key),
      Crypto.ec_encrypt(aes_key, Crypto.node_public_key())
    )
  end

  @doc """
  Initializes the genesis wallets for the UCO distribution:
  - Funding Pool: 38.2%
  - Network Pool: 14.6%
  """
  @spec init_genesis_wallets(network_pool_address :: binary()) :: :ok
  def init_genesis_wallets(network_pool_address) do
    genesis_transfers =
      Enum.map(Application.get_env(:uniris_core, __MODULE__)[:genesis_pools], fn {_,
                                                                                  [
                                                                                    public_key:
                                                                                      public_key,
                                                                                    amount: amount
                                                                                  ]} ->
        %Transfer{
          to: public_key |> Base.decode16!() |> Crypto.hash(),
          amount: amount
        }
      end)

    Logger.info("Create UCO distribution genesis transaction")

    tx =
      Transaction.new(
        :transfer,
        %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers:
                genesis_transfers ++
                  [
                    %Transfer{to: network_pool_address, amount: 1.46e9}
                  ]
            }
          }
        },
        :crypto.strong_rand_bytes(32),
        0
      )

    initial_balance = 1.0e10 + 0.1

    tx
    |> self_validation!(%Context{
      unspent_outputs: [%UnspentOutput{from: tx.address, amount: initial_balance}]
    })
    |> self_replication()
  end

  @doc """
  Self validate a transaction during the network bootstrap
  AKA: when there is only one node in the network
  """
  @spec self_validation!(
          Transaction.pending(),
          context :: Context.t()
        ) :: Transaction.validated()
  def self_validation!(
        tx = %Transaction{},
        context \\ %Context{}
      ) do
    unless Transaction.valid_pending_transaction?(tx) do
      raise "Invalid transaction"
    end

    node_public_key = Crypto.node_public_key()

    validation_stamp =
      ValidationStamp.new(
        tx,
        context,
        node_public_key,
        node_public_key,
        [node_public_key]
      )

    cross_validation_stamp = CrossValidationStamp.new(validation_stamp, [])

    %{tx | validation_stamp: validation_stamp, cross_validation_stamps: [cross_validation_stamp]}
  end

  @spec self_replication(Transaction.validated()) :: :ok
  def self_replication(tx = %Transaction{}) do
    UnirisCore.Storage.write_transaction_chain([tx])
    Beacon.add_transaction(tx)
  end
end
