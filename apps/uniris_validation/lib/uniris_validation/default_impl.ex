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
  alias UnirisElection, as: Election
  alias UnirisCrypto, as: Crypto
  alias UnirisP2P, as: P2P
  alias UnirisP2P.Node
  alias UnirisChain.Transaction.ValidationStamp.NodeMovements

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
          validation_node_views :: bitstring(),
          storage_node_views :: bitstring()
        ) :: :ok
  def add_context(
        tx_address,
        validation_node_public_key,
        previous_storage_node_public_keys,
        validation_node_views,
        storage_node_views
      ) do
    Mining.add_context(
      tx_address,
      validation_node_public_key,
      previous_storage_node_public_keys,
      validation_node_views,
      storage_node_views
    )
  end

  @impl true
  @spec set_replication_tree(binary(), list(bitstring())) :: :ok
  def set_replication_tree(tx_address, tree) do
    Mining.set_replication_tree(tx_address, tree)
  end

  @impl true
  @spec replicate_transaction(Transaction.validated()) ::
          :ok | {:error, :invalid_transaction}
  def replicate_transaction(tx = %Transaction{}) do
    storage_nodes_keys = Enum.map(Election.storage_nodes(tx.address), & &1.last_public_key)
     %Node{authorized?: authorized_node?} = Node.details(Crypto.node_public_key())

    if Crypto.node_public_key() in storage_nodes_keys and authorized_node? do
      # As next storage pool
      case Replication.full_validation(tx) do
        {:ok, [tx | []]} ->
          Chain.store_transaction(tx)
          acknowledge_storage(tx)
          UnirisSync.publish_new_transaction(tx)

        {:ok, chain = [_ | _]} ->
          Chain.store_transaction_chain(chain)
          acknowledge_storage(tx)
          UnirisSync.publish_new_transaction(tx)

        _ ->
          {:error, :invalid_transaction}
      end
    else
      # As unspent ouputs nodes or beacon chain nodes
      case Replication.lite_validation(tx) do
        :ok ->
          Chain.store_transaction(tx)
          UnirisSync.publish_new_transaction(tx)

        _ ->
          {:error, :invalid_transaction}
      end
    end
  end

  defp acknowledge_storage(
         tx = %Transaction{
           validation_stamp: %ValidationStamp{node_movements: %NodeMovements{rewards: rewards}}
         }
       ) do
    [{welcome_node_public_key, _} | _] = rewards

    Task.start(fn ->
      P2P.send_message(welcome_node_public_key, {:acknowledge_storage, tx.address})
    end)
  end
end
