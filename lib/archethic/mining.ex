defmodule Archethic.Mining do
  @moduledoc """
  Handle the ARCH consensus behavior and transaction mining
  """

  alias Archethic.Contracts.Contract
  alias Archethic.Crypto

  alias Archethic.Election
  alias Archethic.Election.ValidationConstraints

  alias __MODULE__.DistributedWorkflow
  alias __MODULE__.Fee
  alias __MODULE__.PendingTransactionValidation
  alias __MODULE__.StandaloneWorkflow
  alias __MODULE__.WorkerSupervisor
  alias __MODULE__.WorkflowRegistry

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.ReplicationError

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp

  alias Archethic.Utils

  require Logger

  use Retry

  @protocol_version 1

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
  @spec get_validation_nodes(Transaction.t(), DateTime.t()) :: list(Node.t())
  def get_validation_nodes(
        tx = %Transaction{address: tx_address},
        current_date = %DateTime{} \\ DateTime.utc_now()
      ) do
    sorting_seed = Election.validation_nodes_election_seed_sorting(tx, current_date)

    node_list = P2P.authorized_and_available_nodes(current_date)
    storage_nodes = Election.chain_storage_nodes(tx_address, node_list)

    validation_constraints =
      %ValidationConstraints{
        min_validation_nodes: min_validation_nodes_fun
      } = Election.get_validation_constraints()

    min_validations = min_validation_nodes_fun.(length(node_list))

    do_get_validation_nodes(
      tx,
      sorting_seed,
      node_list,
      storage_nodes,
      validation_constraints,
      min_validations
    )
  end

  defp do_get_validation_nodes(
         tx,
         sorting_seed,
         node_list,
         storage_nodes,
         validation_constraints,
         min_validations,
         iteration \\ 1
       )

  defp do_get_validation_nodes(
         tx,
         sorting_seed,
         node_list,
         storage_nodes,
         validation_constraints = %ValidationConstraints{},
         min_validations,
         iteration
       ) do
    validation_nodes =
      Election.validation_nodes(
        tx,
        sorting_seed,
        node_list,
        validation_constraints,
        iteration
      )

    %{available_nodes: available_nodes, unavailable_nodes: unavailable_nodes} =
      Enum.reduce(
        validation_nodes,
        %{available_nodes: [], unavailable_nodes: []},
        fn node, acc ->
          if P2P.node_connected?(node) do
            Map.update!(acc, :available_nodes, &[node | &1])
          else
            Map.update!(acc, :unavailable_nodes, &[node | &1])
          end
        end
      )

    best_candidates = available_nodes -- storage_nodes
    nb_best_candidates = length(best_candidates)

    if nb_best_candidates >= min_validations do
      Enum.reverse(best_candidates)
    else
      # We don't have enough validation from the available validation nodes (best candidates: storage nodes reduced)
      # If we still have some authorized nodes, we try to lower the geographical constraints to take more nodes
      # Otherwise we take the available nodes (including the ones acting as the storage nodes)

      remaining_nodes = (node_list -- best_candidates) -- unavailable_nodes

      nb_remaining_available_nodes =
        remaining_nodes
        |> Enum.filter(&P2P.node_connected?/1)
        |> Enum.count()

      if (nb_best_candidates < min_validations and nb_remaining_available_nodes == 0) or
           iteration == 3 do
        Enum.reverse(available_nodes)
      else
        do_get_validation_nodes(
          tx,
          sorting_seed,
          node_list,
          storage_nodes,
          validation_constraints,
          min_validations,
          iteration + 1
        )
      end
    end
  end

  @doc """
  Determines if the election of validation nodes performed by the welcome node is valid

  Because we cannot know at certain time if a node was unavailable from the welcome node point of view
  due to the refining of election, we can't do further verification abouts the nb validators or the geo patch distribution.

  Hence the only deterministic check available is the authorized nodes capability.
  By using the sorted list of nodes, the check will be faster in most of cases, as the first nodes will be located at the head of the list
  """
  @spec valid_election?(
          transaction :: Transaction.t(),
          validation_node_public_keys :: list(Crypto.key()),
          sorted_nodes :: list(Node.t())
        ) :: boolean()
  def valid_election?(tx = %Transaction{}, validation_node_public_keys, sorted_nodes)
      when is_list(validation_node_public_keys) and is_list(sorted_nodes) do
    if Enum.all?(
         validation_node_public_keys,
         &Utils.key_in_node_list?(sorted_nodes, &1)
       ) do
      nb_nodes = length(sorted_nodes)

      %ValidationConstraints{
        min_validation_nodes: min_validation_nodes_fun,
        validation_number: validation_number_fun,
        min_geo_patch: min_geo_patch_fun
      } = Election.get_validation_constraints()

      nb_validations =
        min(
          Election.hypergeometric_distribution(nb_nodes),
          validation_number_fun.(tx, nb_nodes)
        )

      patches =
        sorted_nodes
        |> Enum.map(& &1.geo_patch)
        |> MapSet.new()

      # We need to check if the number of patch is sufficient, this case might happens when all the nodes requested are in the same geo patch (ex: dev mode)
      if MapSet.size(patches) > 1 do
        min_geo_patch = min_geo_patch_fun.()

        node_list = P2P.get_nodes_info(validation_node_public_keys)
        min_nb_nodes = min_validation_nodes_fun.(nb_nodes)

        validation_range = Range.new(min_nb_nodes, nb_validations)

        valid_constraints_iterations?(node_list, validation_range, min_geo_patch, %{
          zones: MapSet.new(),
          nb_nodes: 0,
          node_list: node_list
        }) and ensure_order?(sorted_nodes, validation_node_public_keys)
      else
        ensure_order?(sorted_nodes, validation_node_public_keys)
      end
    end
  end

  # Ensure the nodes are sorted in the right order even if some jumps are present due to the unavailability of nodes
  defp ensure_order?(sorted_nodes, validation_node_public_keys) do
    sorted_nodes_numbered =
      sorted_nodes
      |> Enum.map(& &1.last_public_key)
      |> Enum.with_index()
      |> Enum.into(Map.new())

    acc =
      Enum.reduce_while(validation_node_public_keys, %{prev_index: -1}, fn node_public_key, acc ->
        index = Map.get(sorted_nodes_numbered, node_public_key)

        case acc do
          %{prev_index: -1} ->
            {:cont, Map.put(acc, :prev_index, index)}

          %{prev_index: prev_index} when index <= prev_index ->
            {:halt, %{invalid?: true}}

          %{prev_index: prev_index} when index > prev_index ->
            {:cont, Map.put(acc, :prev_index, index)}
        end
      end)

    not Map.get(acc, :invalid?, false)
  end

  defp valid_constraints_iterations?(
         node_list,
         validation_range,
         min_geo_patch,
         acc,
         iteration \\ 1
       )

  defp valid_constraints_iterations?(
         [%Node{geo_patch: geo_patch} | r],
         validation_range,
         min_geo_patch,
         acc = %{zones: zones},
         iteration
       ) do
    {zone, _} = String.split_at(geo_patch, iteration)

    if MapSet.member?(zones, zone) do
      valid_constraints_iterations?(r, validation_range, min_geo_patch, acc, iteration)
    else
      new_acc =
        acc
        |> Map.update!(:nb_nodes, &(&1 + 1))
        |> Map.update!(:zones, &MapSet.put(&1, zone))

      valid_constraints_iterations?(r, validation_range, min_geo_patch, new_acc, iteration)
    end
  end

  defp valid_constraints_iterations?(
         _node_list,
         _validation_range,
         _min_geo_patch,
         _acc,
         _iterations = 4
       ),
       do: false

  defp valid_constraints_iterations?(
         [],
         validation_range,
         min_geo_patch,
         acc = %{zones: zones, nb_nodes: nb_nodes, node_list: node_list},
         iteration
       ) do
    # Check if the constraints are satisified
    if MapSet.size(zones) >= min_geo_patch and nb_nodes in validation_range do
      true
    else
      new_acc =
        acc
        |> Map.put(:zones, MapSet.new())
        |> Map.put(:nb_nodes, 0)

      valid_constraints_iterations?(
        node_list,
        validation_range,
        min_geo_patch,
        new_acc,
        iteration + 1
      )
    end
  end

  @doc """
  Add transaction mining context which built by another cross validation node
  """
  @spec add_mining_context(
          address :: binary(),
          validation_node_public_key :: Crypto.key(),
          previous_storage_nodes_keys :: list(Crypto.key()),
          chain_storage_nodes_view :: bitstring(),
          beacon_storage_nodes_view :: bitstring(),
          io_storage_nodes_view :: bitstring()
        ) ::
          :ok
  def add_mining_context(
        tx_address,
        validation_node_public_key,
        previous_storage_nodes_keys,
        chain_storage_nodes_view,
        beacon_storage_nodes_view,
        io_storage_nodes_view
      ) do
    tx_address
    |> get_mining_process!(Message.get_max_timeout())
    |> DistributedWorkflow.add_mining_context(
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
          ValidationStamp.t(),
          replication_tree :: %{
            chain: list(bitstring()),
            beacon: list(bitstring()),
            IO: list(bitstring())
          },
          confirmed_cross_validation_nodes :: bitstring()
        ) :: :ok
  def cross_validate(
        tx_address,
        stamp = %ValidationStamp{},
        replication_tree = %{chain: chain_tree, beacon: beacon_tree, IO: io_tree},
        confirmed_cross_validation_nodes
      )
      when is_list(chain_tree) and is_list(beacon_tree) and is_list(io_tree) do
    tx_address
    |> get_mining_process!()
    |> DistributedWorkflow.cross_validate(
      stamp,
      replication_tree,
      confirmed_cross_validation_nodes
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
          reason :: ReplicationError.reason(),
          Crypto.key()
        ) :: :ok
  def notify_replication_error(tx_address, error_reason, node_public_key) do
    pid = get_mining_process!(tx_address, 1_000)

    if pid,
      do: DistributedWorkflow.replication_error(pid, error_reason, node_public_key)

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
  Validate a pending transaction
  """
  @spec validate_pending_transaction(Transaction.t()) :: :ok | {:error, any()}
  defdelegate validate_pending_transaction(tx), to: PendingTransactionValidation, as: :validate

  @doc """
  Get the transaction fee
  """
  @spec get_transaction_fee(Transaction.t(), float(), DateTime.t()) :: non_neg_integer()
  defdelegate get_transaction_fee(tx, uco_price_in_usd, timestamp), to: Fee, as: :calculate
end
