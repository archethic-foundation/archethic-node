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
  alias __MODULE__.Replication
  alias __MODULE__.Mining
  alias UnirisP2P, as: P2P
  alias UnirisChain.Transaction.ValidationStamp.NodeMovements
  alias UnirisSync, as: Sync

  @behaviour UnirisValidation.Impl

  require Logger

  @impl true
  @spec start_mining(Transaction.pending(), UnirisCrypto.key(), list(UnirisCrypto.key())) ::
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
             public_key :: UnirisCrypto.key()}
        ) :: :ok
  def add_cross_validation_stamp(tx_address, stamp = {_sig, _inconsistencies, _public_key}) do
    Mining.add_cross_validation_stamp(tx_address, stamp)
  end

  @impl true
  @spec add_context(
          tx_address :: binary(),
          validation_node_public_key :: UnirisCrypto.key(),
          previous_storage_node_public_keys :: list(UnirisCrypto.key()),
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
        Sync.load_transaction(tx)

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
        Sync.load_transaction(tx)

      _ ->
        Chain.store_ko_transaction(tx)
    end
  end

  @impl true
  @spec replicate_address(binary(), non_neg_integer()) :: :ok
  def replicate_address(address, timestamp) do
    Sync.add_transaction_to_beacon(address, timestamp)
  end
end
