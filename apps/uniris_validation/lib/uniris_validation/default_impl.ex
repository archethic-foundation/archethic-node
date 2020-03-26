defmodule UnirisValidation.DefaultImpl do
  @moduledoc """
  Uniris Validation workflow using atomic commitment to support the ARCH consensus.

  This module represents each transaction validation in the system and is responsible to
  orchestrate the state holding for the job processed (Context building, Node movements, Ledger movements)
  """

  alias UnirisChain, as: Chain
  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp
  alias UnirisValidation.MiningSupervisor
  alias UnirisP2P, as: P2P
  alias UnirisChain.Transaction.ValidationStamp.NodeMovements
  alias UnirisBeacon, as: Beacon
  alias UnirisPubSub, as: PubSub
  alias __MODULE__.Replication
  alias __MODULE__.Mining
  alias __MODULE__.Reward
  alias __MODULE__.ProofOfWork
  alias __MODULE__.ProofOfIntegrity
  alias __MODULE__.Stamp
  alias __MODULE__.Fee

  @behaviour UnirisValidation.Impl

  require Logger

  @impl true
  @spec start_mining(Transaction.pending(), UnirisUnirisCrypto.key(), list(UnirisUnirisCrypto.key())) ::
          {:ok, pid()}
  def start_mining(tx = %Transaction{}, welcome_node_public_key, validation_node_public_keys) do
    DynamicSupervisor.start_child(
      MiningSupervisor,
      {Mining,
       transaction: tx,
       welcome_node_public_key: welcome_node_public_key,
       validation_node_public_keys: validation_node_public_keys}
    )
  end

  @impl true
  @spec cross_validate(binary(), ValidationStamp.t()) ::
          {signature :: binary(), inconsistencies :: list(atom())}
  def cross_validate(tx_address, stamp = %ValidationStamp{}) do
    Mining.cross_validate(tx_address, stamp)
  end

  @impl true
  @spec add_cross_validation_stamp(
          tx_address :: binary(),
          stamp ::
            {signature :: binary(), inconsistencies :: list(atom),
             public_key :: UnirisUnirisCrypto.key()}
        ) :: :ok
  def add_cross_validation_stamp(tx_address, stamp = {_sig, _inconsistencies, _public_key}) do
    Mining.add_cross_validation_stamp(tx_address, stamp)
  end

  @impl true
  @spec add_context(
          tx_address :: binary(),
          validation_node_public_key :: UnirisUnirisCrypto.key(),
          previous_storage_node_public_keys :: list(UnirisUnirisCrypto.key()),
          validation_nodes_view :: bitstring(),
          chain_storage_nodes_view :: bitstring(),
          beacon_storage_nodes_view :: bitstring()
        ) :: :ok
  def add_context(
        tx_address,
        validation_node_public_key,
        previous_storage_node_public_keys,
        validation_nodes_view,
        chain_storage_nodes_view,
        beacon_storage_nodes_view
      ) do
    Mining.add_context(
      tx_address,
      validation_node_public_key,
      previous_storage_node_public_keys,
      validation_nodes_view,
      chain_storage_nodes_view,
      beacon_storage_nodes_view
    )
  end

  @impl true
  @spec set_replication_trees(binary(), list(list(bitstring()))) :: :ok
  def set_replication_trees(tx_address, trees) do
    Mining.set_replication_trees(tx_address, trees)
  end

  @impl true
  @spec replicate_chain(Transaction.validated()) :: :ok
  def replicate_chain(
        tx = %Transaction{
          validation_stamp: %ValidationStamp{node_movements: %NodeMovements{rewards: rewards}}
        }
      ) do
    case Replication.full_validation(tx) do
      {:error, :invalid_transaction} ->
        Chain.store_ko_transaction(tx)

      {:ok, chain} ->
        Chain.store_transaction_chain(chain)
        PubSub.notify_new_transaction(tx)

        # Notify welcome node about the storage of the transaction
        [{welcome_node_public_key, _} | _] = rewards
        spawn fn ->
          P2P.send_message(welcome_node_public_key, {:acknowledge_storage, tx.address})
        end
    end
  end

  @impl true
  @spec replicate_transaction(Transaction.validated()) :: :ok
  def replicate_transaction(tx = %Transaction{}) do
    case Replication.lite_validation(tx) do
      :ok ->
        Chain.store_transaction(tx)
        PubSub.notify_new_transaction(tx)

      _ ->
        Chain.store_ko_transaction(tx)
    end
  end

  @impl true
  @spec replicate_address(binary(), non_neg_integer()) :: :ok
  def replicate_address(address, timestamp) do
    Beacon.add_transaction(address, timestamp)
  end

  @impl true
  @spec get_proof_of_work(Transaction.pending()) :: {:ok, UnirisCrypto.key()} | {:error, :not_found}
  def get_proof_of_work(tx = %Transaction{}) do
    ProofOfWork.run(tx)
  end

  @impl true
  @spec get_proof_of_integrity(list(Transaction.pending())) :: binary()
  def get_proof_of_integrity([tx | []]) do
    ProofOfIntegrity.from_transaction(tx)
  end

  def get_proof_of_integrity(transaction_chain) do
    ProofOfIntegrity.from_chain(transaction_chain)
  end

  @impl true
  @spec get_transaction_fee(Transaction.pending()) :: float()
  def get_transaction_fee(tx = %Transaction{}) do
    Fee.from_transaction(tx)
  end

  @impl true
  @spec get_node_rewards(float(), UnirisCrypto.key(), UnirisCrypto.key(), list(UnirisCrypto.key()), list(UnirisCrypto.key())) :: list({UnirisCrypto.key(), float()})
  def get_node_rewards(fee, welcome_node, coordinator_node, validation_nodes, storage_nodes) do
    Reward.distribute_fee(fee, welcome_node, coordinator_node, validation_nodes, storage_nodes)
  end

  @impl true
  @spec get_cross_validation_stamp(ValidationStamp.t(), list(atom())) :: {binary(), list(atom()), UnirisCrypto.key()}
  def get_cross_validation_stamp(stamp = %ValidationStamp{}, inconsistencies) do
    Stamp.create_cross_validation_stamp(stamp, inconsistencies, UnirisCrypto.node_public_key())
  end
end
