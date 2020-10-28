defmodule Uniris.Mining do
  @moduledoc """
  Handle the ARCH consensus behavior and transaction mining
  """

  alias Uniris.Crypto

  alias Uniris.Election

  alias Uniris.Governance
  alias Uniris.Governance.Code.Proposal, as: CodeProposal

  alias __MODULE__.DistributedWorkflow
  alias __MODULE__.StandaloneWorkflow
  alias __MODULE__.WorkerSupervisor
  alias __MODULE__.WorkflowRegistry

  alias Uniris.P2P
  alias Uniris.P2P.Message.FirstPublicKey
  alias Uniris.P2P.Message.GetFirstPublicKey
  alias Uniris.P2P.Message.NotFound

  alias Uniris.Replication

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.CrossValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Keys

  alias Uniris.Utils

  require Logger

  @doc """
  Start mining process for a given transaction.
  """
  @spec start(
          transaction :: Transaction.pending(),
          welcome_node_public_key :: Uniris.Crypto.key(),
          validation_node_public_keys :: list(Uniris.Crypto.key())
        ) :: {:ok, pid()}
  def start(tx = %Transaction{}, welcome_node_public_key, [_ | []]) do
    StandaloneWorkflow.start_link(
      transaction: tx,
      welcome_node: welcome_node_public_key,
      validation_nodes: [P2P.get_node_info()],
      node_public_key: Crypto.node_public_key()
    )
  end

  def start(tx = %Transaction{}, welcome_node_public_key, validation_node_public_keys)
      when is_binary(welcome_node_public_key) and is_list(validation_node_public_keys) do
    DynamicSupervisor.start_child(WorkerSupervisor, {
      DistributedWorkflow,
      transaction: tx,
      welcome_node: P2P.get_node_info!(welcome_node_public_key),
      validation_nodes: Enum.map(validation_node_public_keys, &P2P.get_node_info!/1),
      node_public_key: Crypto.node_public_key()
    })
  end

  @doc """
  Return the list of validation nodes for a given transaction and the current validation constraints
  """
  @spec transaction_validation_nodes(Transaction.t()) :: list(Node.t())
  def transaction_validation_nodes(tx = %Transaction{}) do
    constraints = Election.get_validation_constraints()
    node_list = P2P.list_nodes(authorized?: true, availability: :global)
    Election.validation_nodes(tx, node_list, constraints)
  end

  @doc """
  Determines if the election of validation nodes performed by the welcome node is valid
  """
  @spec valid_election?(Transaction.t(), list(Crypto.key())) :: boolean()
  def valid_election?(tx = %Transaction{}, validation_node_public_keys)
      when is_list(validation_node_public_keys) do
    nodes = transaction_validation_nodes(tx)

    elected_node_public_keys =
      tx
      |> Election.validation_nodes(nodes)
      |> Enum.map(& &1.last_public_key)

    elected_node_public_keys == validation_node_public_keys
  end

  @doc """
  Determines if the transaction is accepted into the network
  """
  @spec accept_transaction?(Transaction.t()) :: boolean()
  def accept_transaction?(tx = %Transaction{}) do
    if Transaction.verify_previous_signature?(tx) do
      do_accept_transaction?(tx)
    else
      false
    end
  end

  defp do_accept_transaction?(%Transaction{
         type: :node,
         data: %TransactionData{content: content}
       }) do
    Regex.match?(~r/(?<=ip:|port:).*/m, content)
  end

  defp do_accept_transaction?(%Transaction{
         type: :node_shared_secrets,
         data: %TransactionData{
           keys: keys = %Keys{secret: secret, authorized_keys: authorized_keys}
         },
         previous_public_key: previous_public_key
       })
       when is_binary(secret) and byte_size(secret) > 0 and map_size(authorized_keys) > 0 do
    nodes = P2P.list_nodes()

    last_tx =
      Enum.at(TransactionChain.list_transactions_by_type(:node_shared_secrets, [:address]), 0)

    case last_tx do
      nil ->
        Enum.all?(Keys.list_authorized_keys(keys), &Utils.key_in_node_list?(nodes, &1))

      %Transaction{address: prev_address} ->
        Crypto.hash(previous_public_key) == prev_address &&
          Enum.all?(Keys.list_authorized_keys(keys), &Utils.key_in_node_list?(nodes, &1))
    end
  end

  defp do_accept_transaction?(%Transaction{type: :node_shared_secrets}), do: false

  defp do_accept_transaction?(tx = %Transaction{type: :code_proposal}) do
    case CodeProposal.from_transaction(tx) do
      {:ok, prop} ->
        Governance.valid_code_changes?(prop)

      _ ->
        false
    end
  end

  defp do_accept_transaction?(
         tx = %Transaction{
           type: :code_approval,
           data: %TransactionData{recipients: [proposal_address]}
         }
       ) do
    first_public_key = get_first_public_key(tx)

    with true <- Governance.pool_member?(first_public_key, :technical_council),
         {:ok, prop} <- Governance.get_code_proposal(proposal_address),
         previous_address <- Transaction.previous_address(tx),
         false <- CodeProposal.signed_by?(prop, previous_address) do
      true
    end
  end

  defp do_accept_transaction?(_), do: true

  defp get_first_public_key(tx = %Transaction{previous_public_key: previous_public_key}) do
    previous_address = Transaction.previous_address(tx)

    storage_nodes =
      Replication.chain_storage_nodes(previous_address, P2P.list_nodes(availability: :global))

    response_message =
      storage_nodes
      |> P2P.broadcast_message(%GetFirstPublicKey{address: previous_address})
      |> Enum.at(0)

    case response_message do
      %NotFound{} ->
        previous_public_key

      %FirstPublicKey{public_key: public_key} ->
        public_key
    end
  end

  @doc """
  Add transaction mining context which built by another cross validation node
  """
  @spec add_mining_context(
          address :: binary(),
          validation_node_public_key :: Crypto.key(),
          previous_storage_nodes_keys :: list(Crypto.key()),
          cross_validation_nodes_view :: bitstring(),
          chain_storage_nodes_view :: bitstring(),
          beacon_storage_nodes_view :: bitstring()
        ) ::
          :ok
  def add_mining_context(
        tx_address,
        validation_node_public_key,
        previous_storage_nodes_keys,
        cross_validation_nodes_view,
        chain_storage_nodes_view,
        beacon_storage_nodes_view
      ) do
    tx_address
    |> get_mining_process!()
    |> DistributedWorkflow.add_mining_context(
      validation_node_public_key,
      P2P.get_nodes_info(previous_storage_nodes_keys),
      cross_validation_nodes_view,
      chain_storage_nodes_view,
      beacon_storage_nodes_view
    )
  end

  @doc """
  Cross validate the validation stamp and the replication tree produced by the coordinator

  If no inconsistencies, the validation stamp is stamped by the the node public key.
  Otherwise the inconsistencies will be signed.
  """
  @spec cross_validate(
          address :: binary(),
          ValidationStamp.t(),
          replication_tree :: list(bitstring())
        ) :: :ok
  def cross_validate(tx_address, stamp = %ValidationStamp{}, replication_tree)
      when is_list(replication_tree) do
    tx_address
    |> get_mining_process!()
    |> DistributedWorkflow.cross_validate(stamp, replication_tree)
  end

  @doc """
  Add a cross validation stamp to the transaction mining process
  """
  @spec add_cross_validation_stamp(binary(), stamp :: CrossValidationStamp.t()) :: :ok
  def add_cross_validation_stamp(tx_address, stamp = %CrossValidationStamp{}) do
    tx_address
    |> get_mining_process!()
    |> DistributedWorkflow.add_cross_validation_stamp(stamp)
  end

  defp get_mining_process!(tx_address) do
    case Registry.lookup(WorkflowRegistry, tx_address) do
      [{pid, _}] ->
        pid

      _ ->
        raise "No mining process for the transaction"
    end
  end
end
