defmodule UnirisValidation do
  @moduledoc """
  Uniris Validation workflow using atomic commitment to support the ARCH consensus.

  This module represents each transaction validation in the system and is responsible to
  orchestrate the state holding for the job processed (Context building, Node movements, Ledger movements)
  """

  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp

  @behaviour __MODULE__.Impl

  @doc """
  Initiate the validation workflow for the given transaction.

  A new process is spawn responsible to gather context and forward information to other validation nodes.

  If the node is the coordinator, it will run the proof of work and manage the acknowledgements of jobs coming from the cross validation nodes.
  """

  @impl true
  @spec start_mining(Transaction.pending(), UnirisCrypto.key(), list(UnirisCrypto.key())) ::
          {:ok, pid()}
  def start_mining(tx = %Transaction{}, welcome_node_public_key, validation_node_public_keys) do
    impl().start_mining(tx, welcome_node_public_key, validation_node_public_keys)
  end

  @doc """
  Cross validate the stamp coming from a coordinator and return a signature with or without a list of inconsistencies.
  """
  @impl true
  @spec cross_validate(binary(), ValidationStamp.t()) ::
          {signature :: binary(), inconsistencies :: list(atom()),
           public_key :: UnirisCrypto.key()}
  def cross_validate(tx_address, stamp = %ValidationStamp{}) do
    impl().cross_validate(tx_address, stamp)
  end

  @doc """
  Add a cross validation coming from other validation node to the transaction processor.

  It includes the signature of the cross validation stamp, the list of inconsistencies and theS
  node emitter of the validation
  """

  @impl true
  @spec add_cross_validation_stamp(
          tx_address :: binary(),
          stamp ::
            {signature :: binary(), inconsistencies :: list(atom),
             public_key :: UnirisCrypto.key()}
        ) :: :ok
  def add_cross_validation_stamp(tx_address, stamp = {_sig, _inconsistencies, _public_key}) do
    impl().add_cross_validation_stamp(tx_address, stamp)
  end

  @doc """
  Add a context built from a validation node to the transaction processor.

  Context view include the previous storage used to rebuilt the context and view of the availability
  from the elected validation nodes and the next storage pool.
  """
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
    impl().add_context(
      tx_address,
      validation_node_public_key,
      previous_storage_node_public_keys,
      validation_nodes_view,
      chain_storage_nodes_view,
      beacon_storage_nodes_view
    )
  end

  @doc """
  Add the replication trees (chain and beacon chain) computed by the coordinator to the mining process.

  Based on the bitstring positionning, the validation node can find out which are the nodes to replicate on
  """
  @impl true
  @spec set_replication_trees(binary(), list(list(bitstring()))) :: :ok
  def set_replication_trees(tx_address, trees) do
    impl().set_replication_trees(tx_address, trees)
  end

  @doc """
  Validate and store a transaction chain

  A full validation is performed to check:
  - context building, ledger movements, node movements, chain integrity, etc.
  """
  @impl true
  @spec replicate_chain(Transaction.validated()) :: :ok
  def replicate_chain(tx = %Transaction{}) do
    impl().replicate_chain(tx)
  end

  @doc """
  Validate and a store a single transaction. Used for unspent output transactions

  A lite version of the validation is performed to ensure the cryptography integrity and atomic commitment
  """
  @impl true
  @spec replicate_transaction(Transaction.validated()) :: :ok
  def replicate_transaction(tx = %Transaction{}) do
    impl().replicate_transaction(tx)
  end

  @doc """
  Propose the address to the beacon chain
  """
  @impl true
  @spec replicate_address(binary(), non_neg_integer()) :: :ok
  def replicate_address(address, timestamp) do
    impl().replicate_address(address, timestamp)
  end

  @impl true
  @spec get_proof_of_work(Transaction.pending()) :: {:ok, UnirisCrypto.key()} | {:error, :not_found}
  def get_proof_of_work(tx = %Transaction{}) do
    impl().get_proof_of_work(tx)
  end

  @impl true
  @spec get_proof_of_integrity(list(Transaction.pending())) :: binary()
  def get_proof_of_integrity(transaction_chain) do
    impl().get_proof_of_integrity(transaction_chain)
  end

  @impl true
  @spec get_transaction_fee(Transaction.pending()) :: float()
  def get_transaction_fee(tx = %Transaction{}) do
    impl().get_transaction_fee(tx)
  end

  @impl true
  @spec get_node_rewards(float(), UnirisCrypto.key(), UnirisCrypto.key(), list(UnirisCrypto.key()), list(UnirisCrypto.key())) :: list({UnirisCrypto.key(), float()})
  def get_node_rewards(fee, welcome_node, coordinator_node, validation_nodes, storage_nodes) do
    impl().get_node_rewards(fee, welcome_node, coordinator_node, validation_nodes, storage_nodes)
  end

  @impl true
  @spec get_cross_validation_stamp(ValidationStamp.t(), list(atom())) :: {binary(), list(atom()), UnirisCrypto.key()}
  def get_cross_validation_stamp(stamp = %ValidationStamp{}, inconsistencies) do
    impl().get_cross_validation_stamp(stamp, inconsistencies)
  end

  defp impl() do
    Application.get_env(:uniris_validation, :impl, __MODULE__.DefaultImpl)
  end
end
