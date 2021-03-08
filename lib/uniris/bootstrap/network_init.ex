defmodule Uniris.Bootstrap.NetworkInit do
  @moduledoc """
  Set up the network by initialize genesis information (i.e storage nonce, coinbase transactions)

  Those functions are only executed by the first node bootstrapping on the network
  """

  alias Uniris.BeaconChain

  alias Uniris.Bootstrap

  alias Uniris.Crypto

  alias Uniris.Mining

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.Replication

  alias Uniris.SharedSecrets

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.CrossValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Ledger
  alias Uniris.TransactionChain.TransactionData.UCOLedger
  alias Uniris.TransactionChain.TransactionData.UCOLedger.Transfer

  require Logger

  @genesis_pools Application.compile_env(:uniris, __MODULE__)[:genesis_pools]
  @genesis_seed Application.compile_env(:uniris, __MODULE__)[:genesis_seed]

  @doc """
  Initialize the storage nonce and load it into the keystore
  """
  @spec create_storage_nonce() :: :ok
  def create_storage_nonce do
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
    secret_key = :crypto.strong_rand_bytes(32)
    encrypted_secret_key = Crypto.ec_encrypt(secret_key, Crypto.node_public_key())

    :crypto.strong_rand_bytes(32)
    |> Crypto.aes_encrypt(secret_key)
    |> Crypto.decrypt_and_set_node_shared_secrets_transaction_seed(encrypted_secret_key)

    network_pool_seed
    |> Crypto.aes_encrypt(secret_key)
    |> Crypto.decrypt_and_set_node_shared_secrets_network_pool_seed(encrypted_secret_key)

    daily_nonce_seed = :crypto.strong_rand_bytes(32)

    tx =
      SharedSecrets.new_node_shared_secrets_transaction(
        [Crypto.node_public_key(0)],
        daily_nonce_seed,
        secret_key
      )

    tx
    |> self_validation!()
    |> self_replication()

    P2P.authorize_node(Crypto.node_public_key(0), tx.timestamp)

    Crypto.decrypt_and_set_daily_nonce_seed(
      Crypto.aes_encrypt(daily_nonce_seed, secret_key),
      Crypto.ec_encrypt(secret_key, Crypto.node_public_key())
    )
  end

  @doc """
  Initializes the genesis wallets for the UCO distribution
  """
  @spec init_genesis_wallets(network_pool_address :: binary()) :: :ok
  def init_genesis_wallets(network_pool_address) do
    Logger.info("Create UCO distribution genesis transaction")

    tx =
      network_pool_address
      |> genesis_transfers()
      |> create_genesis_transaction()

    genesis_transfers_amount =
      tx
      |> Transaction.get_movements()
      |> Enum.reduce(0.0, &(&2 + &1.amount))

    tx
    |> self_validation!([
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
    Enum.map(@genesis_pools, fn {_,
                                 [
                                   public_key: public_key,
                                   amount: amount
                                 ]} ->
      %Transfer{
        to: public_key |> Base.decode16!() |> Crypto.hash(),
        amount: amount
      }
    end) ++
      [%Transfer{to: network_pool_address, amount: 1.46e9}]
  end

  def self_validation!(tx = %Transaction{}, unspent_outputs \\ []) do
    case Mining.validate_pending_transaction(tx) do
      {:error, _} ->
        raise "Invalid transaction"

      :ok ->
        operations =
          %LedgerOperations{
            fee: Transaction.fee(tx),
            transaction_movements: resolve_transaction_movements(tx)
          }
          |> LedgerOperations.from_transaction(tx)
          |> LedgerOperations.distribute_rewards(
            %Node{last_public_key: Crypto.node_public_key()},
            %Node{last_public_key: Crypto.node_public_key()},
            [%Node{last_public_key: Crypto.node_public_key()}],
            []
          )
          |> LedgerOperations.consume_inputs(tx.address, unspent_outputs)

        validation_stamp =
          %ValidationStamp{
            proof_of_work: Crypto.node_public_key(),
            proof_of_integrity: tx |> Transaction.serialize() |> Crypto.hash(),
            ledger_operations: operations
          }
          |> ValidationStamp.sign()

        cross_validation_stamp =
          CrossValidationStamp.sign(%CrossValidationStamp{}, validation_stamp)

        %{
          tx
          | validation_stamp: validation_stamp,
            cross_validation_stamps: [cross_validation_stamp]
        }
    end
  end

  defp resolve_transaction_movements(tx) do
    tx
    |> Transaction.get_movements()
    |> Task.async_stream(fn mvt = %TransactionMovement{to: to} ->
      %{mvt | to: TransactionChain.resolve_last_address(to)}
    end)
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Enum.into([], fn {:ok, res} -> res end)
  end

  def self_replication(tx = %Transaction{}) do
    :ok = TransactionChain.write([tx])
    :ok = Replication.ingest_transaction(tx)
    :ok = BeaconChain.add_transaction_summary(tx)
  end
end
