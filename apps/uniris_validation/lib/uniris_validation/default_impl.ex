defmodule UnirisValidation.DefaultImpl do
  @moduledoc """
  Uniris Validation workflow using atomic commitment to support the ARCH consensus.

  This module represents each transaction validation in the system and is responsible to
  orchestrate the state holding for the job processed (Context building, Node movements, Ledger movements)
  """

  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp
  alias UnirisChain.Transaction.ValidationStamp.NodeMovements
  alias UnirisValidation.MiningSupervisor
  alias __MODULE__.Mining
  alias __MODULE__.ContextBuilding
  alias __MODULE__.Stamp
  alias __MODULE__.ProofOfIntegrity
  alias UnirisElection, as: Election
  alias UnirisNetwork, as: Network
  alias UnirisCrypto, as: Crypto

  @behaviour UnirisValidation.Impl

  require Logger

  @doc """
  Initiate the validation workflow for the given transaction.

  A new process is spawn responsible to gather context and forward information to other validation nodes.

  If the node is the coordinator, it will run the proof of work and manage the acknowledgements of jobs coming from the cross validation nodes. 
  """
  @impl true
  @spec start_validation(Transaction.pending(), UnirisCrypto.key(), list(UnirisCrypto.key())) :: {:ok, pid()}
  def start_validation(tx = %Transaction{}, welcome_node_public_key, validation_node_public_keys) do
    DynamicSupervisor.start_child(
      MiningSupervisor,
      {Mining,
       transaction: tx,
       welcome_node_public_key: welcome_node_public_key,
       validation_node_public_keys: validation_node_public_keys}
    )
  end


  @doc """
  Cross validate the stamp coming from a coordinator and return a signature with or without a list of inconsistencies.
  """
  @impl true
  @spec cross_validate(binary(), ValidationStamp.t()) ::
          {signature :: binary(), inconsistencies :: list(atom())}
  def cross_validate(tx_address, stamp = %ValidationStamp{}) do
    Mining.cross_validate(tx_address, stamp)
  end

  @doc """
  Add a cross validation coming from other validation node to the transaction processor.

  It includes the signature of the cross validation stamp, the list of inconsistencies and theS
  node emitter of the validation
  """
  @impl true
  @spec add_cross_validation_stamp(
          tx_address :: binary(),
          stamp :: {signature :: binary(), inconsistencies :: list(atom)},
          validation_node :: UnirisCrypto.key()
        ) :: :ok
  def add_cross_validation_stamp(tx_address, stamp = {_sig, _inconsistencies}, validation_node) do
    Mining.add_cross_validation_stamp(tx_address, stamp, validation_node)
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

  @doc """
  Verify a transaction by download it previous chain and make all the necessary checks:
  - Pending transaction integrity
  - Ledger movements
  - Node movements
  - Atomic commitment
  - Chain integrity

  If the transaction does not match any of these checks, the transaction will be stored as KO
  If the transaction is invalid and if the atomic commitment approved it alo, the transaction will be stored as KO

  Otherwise the transaction will be stored on the TransactionChain
  """
  @impl true
  @spec replicate_transaction(Transaction.validated()) ::
          :ok | {:error, :invalid_transaction} | {:error, :invalid_transaction_chain}
  def replicate_transaction(tx = %Transaction{previous_public_key: prev_pub_key}) do
    if Transaction.valid_pending_transaction?(tx) do
      prev_address = Crypto.hash(prev_pub_key)
      closest_storage_nodes = ContextBuilding.closest_storage_nodes(prev_address)

      case ContextBuilding.download_transaction_context(prev_address, closest_storage_nodes) do
        {:ok, [], unspent_outputs, _} ->
          case verify_transaction_stamp(tx, [], unspent_outputs) do
            :ok ->
              UnirisChain.store_transaction(tx)
          end

        {:ok, chain, unspent_outputs, _} ->
          %Transaction{validation_stamp: %ValidationStamp{proof_of_integrity: poi}} =
            List.first(chain)

          with previous_poi <- ProofOfIntegrity.from_chain(chain),
               true <- previous_poi == poi,
               :ok <- verify_transaction_stamp(tx, chain, unspent_outputs) do
            UnirisChain.store_transaction_chain([tx | chain])
          else
            false ->
              {:error, :invalid_transaction_chain}
          end
      end
    else
      {:error, :invalid_transaction}
    end
  end

  defp verify_transaction_stamp(
         tx = %Transaction{
           validation_stamp:
             stamp = %ValidationStamp{node_movements: %NodeMovements{rewards: rewards}},
           cross_validation_stamps: cross_stamps
         },
         chain,
         unspent_outputs
       ) do
    {coordinator_public_key, _} = Enum.at(rewards, 1)

    validation_nodes = Election.validation_nodes(tx, Network.list_nodes(), Network.daily_nonce())

    with true <- Stamp.valid_cross_validation_stamps?(cross_stamps, stamp),
         :ok <-
           Stamp.check_validation_stamp(
             tx,
             stamp,
             coordinator_public_key,
             Enum.map(validation_nodes, & &1.last_public_key),
             chain,
             unspent_outputs
           ),
         true <- Enum.all?(cross_stamps, &match?({_, [], _}, &1)) do
      :ok
    else
      {:error, _inconsistencies} ->
        if Enum.all?(cross_stamps, &match?({_, [_ | _], _}, &1)) do
          :ok
        else
          {:error, :invalid_transaction}
        end

      false ->
        {:error, :invalid_transaction}
    end
  end

  @doc """
  Determines if the transaction address is under mining
  """
  @impl true
  @spec mining?(binary()) :: boolean()
  def mining?(tx_address) do
    case Registry.lookup(__MODULE__.MiningRegistry, tx_address) do
      [] ->
        false
      _ ->
        true
    end
  end

  @doc """
  Retrieve the mined transaction from an address
  """
  @impl true
  @spec mined_transaction(binary()) :: Transaction.pending()
  def mined_transaction(tx_address) do
    Mining.get_transaction(tx_address)
  end
end
