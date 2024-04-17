defmodule Archethic.Mining do
  @moduledoc """
  Handle the ARCH consensus behavior and transaction mining
  """

  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Contract.State
  alias Archethic.Crypto

  alias Archethic.Election

  alias __MODULE__.DistributedWorkflow
  alias __MODULE__.Error
  alias __MODULE__.Fee
  alias __MODULE__.StandaloneWorkflow
  alias __MODULE__.WorkerSupervisor
  alias __MODULE__.WorkflowRegistry

  alias Archethic.P2P
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.RequestChainLock

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  require Logger

  use Retry

  # version 5->6 the POI changed and is now done with tx.data.recipients.args serialized with :extended mode
  # version 6->7 add Add consumed inputs in tx.validation_stamp.ledger_operations
  # version 7->8 movement resolved address are now the genesis address of the destination
  @protocol_version 8

  @lock_threshold 0.75

  def protocol_version, do: @protocol_version

  @doc """
  Start mining process for a given transaction.
  """
  @spec start(
          transaction :: Transaction.t(),
          welcome_node_public_key :: Crypto.key(),
          validation_node_public_keys :: list(Crypto.key()),
          contract_context :: nil | Contract.Context.t()
        ) :: {:ok, pid()}
  def start(tx = %Transaction{}, welcome_node_public_key, [_ | []], contract_context) do
    StandaloneWorkflow.start_link(
      transaction: tx,
      welcome_node: P2P.get_node_info!(welcome_node_public_key),
      contract_context: contract_context
    )
  end

  def start(
        tx = %Transaction{},
        welcome_node_public_key,
        validation_node_public_keys,
        contract_context
      )
      when is_binary(welcome_node_public_key) and is_list(validation_node_public_keys) do
    DynamicSupervisor.start_child(WorkerSupervisor, {
      DistributedWorkflow,
      transaction: tx,
      welcome_node: P2P.get_node_info!(welcome_node_public_key),
      validation_nodes: Enum.map(validation_node_public_keys, &P2P.get_node_info!/1),
      node_public_key: Crypto.last_node_public_key(),
      contract_context: contract_context
    })
  end

  @doc """
  Elect validation nodes for a transaction
  """
  def get_validation_nodes(tx = %Transaction{address: tx_address, validation_stamp: nil}) do
    current_date = DateTime.utc_now()
    sorting_seed = Election.validation_nodes_election_seed_sorting(tx, current_date)

    node_list = P2P.authorized_and_available_nodes(current_date)

    storage_nodes = Election.chain_storage_nodes(tx_address, node_list)

    Election.validation_nodes(
      tx,
      sorting_seed,
      node_list,
      storage_nodes,
      Election.get_validation_constraints()
    )
  end

  @doc """
  Determines if the election of validation nodes performed by the welcome node is valid
  """
  @spec valid_election?(Transaction.t(), list(Crypto.key())) :: boolean()
  def valid_election?(tx, validation_node_public_keys)
      when is_list(validation_node_public_keys) do
    validation_nodes = get_validation_nodes(tx)
    validation_node_public_keys == Enum.map(validation_nodes, & &1.last_public_key)
  end

  @doc """
  Request storage node to lock the mining of this transaction address and hash
  """
  @spec request_chain_lock(tx :: Transaction.t()) :: :ok | {:error, :already_locked}
  def request_chain_lock(tx = %Transaction{address: address, type: type}) do
    storage_nodes =
      address
      |> Election.storage_nodes(P2P.authorized_and_available_nodes())
      |> Enum.filter(&P2P.node_connected?/1)

    nb_storage_nodes = length(storage_nodes)

    hash =
      tx
      |> Transaction.to_pending()
      |> Transaction.serialize()
      |> Crypto.hash()

    message = %RequestChainLock{address: address, hash: hash}

    aggregated_responses =
      Task.Supervisor.async_stream_nolink(
        Archethic.TaskSupervisor,
        storage_nodes,
        &P2P.send_message(&1, message),
        max_concurrency: nb_storage_nodes,
        timeout: Message.get_timeout(message) + 500,
        on_timeout: :kill_task,
        ordered: false
      )
      |> Stream.filter(&match?({:ok, {:ok, _}}, &1))
      |> Stream.map(fn {:ok, {:ok, res}} -> res end)
      |> Enum.frequencies()

    nb_ok = Map.get(aggregated_responses, %Ok{}, 0)
    total_response = Map.values(aggregated_responses) |> Enum.sum()

    Logger.debug("Received #{nb_ok} lock confirmation on #{total_response}",
      transaction_address: Base.encode16(address),
      transaction_type: type
    )

    if nb_ok / total_response >= @lock_threshold, do: :ok, else: {:error, :already_locked}
  end

  @doc """
  Add transaction mining context which built by another cross validation node
  """
  @spec add_mining_context(
          address :: binary(),
          utxos_hashes :: list(binary()),
          validation_node_public_key :: Crypto.key(),
          previous_storage_nodes_keys :: list(Crypto.key()),
          chain_storage_nodes_view :: bitstring(),
          beacon_storage_nodes_view :: bitstring(),
          io_storage_nodes_view :: bitstring()
        ) ::
          :ok
  def add_mining_context(
        tx_address,
        utxos_hashes,
        validation_node_public_key,
        previous_storage_nodes_keys,
        chain_storage_nodes_view,
        beacon_storage_nodes_view,
        io_storage_nodes_view
      ) do
    tx_address
    |> get_mining_process!(Message.get_max_timeout())
    |> DistributedWorkflow.add_mining_context(
      utxos_hashes,
      validation_node_public_key,
      P2P.get_nodes_info(previous_storage_nodes_keys),
      chain_storage_nodes_view,
      beacon_storage_nodes_view,
      io_storage_nodes_view
    )
  end

  @doc """
  Cross validate the validation stamp and the replication tree produced by the coordinator

  If no inconsistencies, the validation stamp is stamped by the the node public key.
  Otherwise the inconsistencies will be signed.
  """
  @spec cross_validate(
          address :: binary(),
          validatioon_stamp :: ValidationStamp.t(),
          replication_tree :: %{
            chain: list(bitstring()),
            beacon: list(bitstring()),
            IO: list(bitstring())
          },
          confirmed_cross_validation_nodes :: bitstring(),
          aggregated_utxos :: list(VersionedUnspentOutput.t())
        ) :: :ok
  def cross_validate(
        tx_address,
        stamp = %ValidationStamp{},
        replication_tree = %{chain: chain_tree, beacon: beacon_tree, IO: io_tree},
        confirmed_cross_validation_nodes,
        aggregated_utxos
      )
      when is_list(chain_tree) and is_list(beacon_tree) and is_list(io_tree) do
    tx_address
    |> get_mining_process!()
    |> DistributedWorkflow.cross_validate(
      stamp,
      replication_tree,
      confirmed_cross_validation_nodes,
      aggregated_utxos
    )
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

  @doc """
  Confirm the replication from a storage node
  """
  @spec confirm_replication(
          address :: binary(),
          signature :: binary(),
          node_public_key :: Crypto.key()
        ) ::
          :ok
  def confirm_replication(tx_address, signature, node_public_key) do
    pid = get_mining_process!(tx_address, 1000)
    if pid, do: send(pid, {:ack_replication, signature, node_public_key})
    :ok
  end

  @doc """
  Notify replication to the mining process
  """
  @spec notify_replication_error(
          address :: binary(),
          error :: Error.t(),
          Crypto.key()
        ) :: :ok
  def notify_replication_error(tx_address, error, node_public_key) do
    pid = get_mining_process!(tx_address, 1_000)

    if pid, do: DistributedWorkflow.replication_error(pid, error, node_public_key)

    :ok
  end

  @doc """
  Notify about the validation from a replication node
  """
  @spec notify_replication_validation(binary(), Crypto.key()) :: :ok
  def notify_replication_validation(tx_address, node_public_key) do
    pid = get_mining_process!(tx_address, 1_000)
    if pid, do: DistributedWorkflow.add_replication_validation(pid, node_public_key)
    :ok
  end

  defp get_mining_process!(tx_address, timeout \\ 3_000) do
    retry_while with: constant_backoff(100) |> expiry(timeout) do
      case Registry.lookup(WorkflowRegistry, tx_address) do
        [{pid, _}] ->
          {:halt, pid}

        _ ->
          {:cont, nil}
      end
    end
  end

  @doc """
  Return true if the transaction is in mining process
  """
  @spec processing?(binary()) :: boolean()
  def processing?(tx_address) do
    case Registry.lookup(WorkflowRegistry, tx_address) do
      [{_pid, _}] ->
        true

      _ ->
        false
    end
  end

  @doc """
  Get the transaction fee
  """
  @spec get_transaction_fee(
          transaction :: Transaction.t(),
          contract_context :: Contract.Context.t() | nil,
          uco_price_in_usd :: float(),
          timestamp :: DateTime.t(),
          encoded_state :: State.encoded() | nil,
          contract_recipient_fees :: non_neg_integer(),
          protocol_version :: pos_integer()
        ) :: non_neg_integer()
  def get_transaction_fee(
        tx,
        contract_context,
        uco_price_in_usd,
        timestamp,
        encoded_state,
        contract_recipient_fees \\ 0,
        proto_version \\ protocol_version()
      ) do
    Fee.calculate(
      tx,
      contract_context,
      uco_price_in_usd,
      timestamp,
      encoded_state,
      contract_recipient_fees,
      proto_version
    )
  end
end
