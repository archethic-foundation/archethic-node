defmodule Archethic do
  @moduledoc """
  Provides high level functions serving the API and the Explorer
  """

  alias __MODULE__.{Account, BeaconChain, Crypto, Election, P2P, P2P.Node, P2P.Message}
  alias __MODULE__.{SelfRepair, TransactionChain, SharedSecrets, TaskSupervisor}
  alias __MODULE__.Contracts.{Interpreter, Contract}

  alias Message.{NewTransaction, NotFound, StartMining}
  alias Message.{Balance, GetBalance, GetTransactionSummary}
  alias Message.{StartMining, Ok, TransactionSummaryMessage}

  alias TransactionChain.{Transaction, TransactionInput, TransactionSummary}

  require Logger

  @doc """
    Returns true if a node is up and false if it is down
  """
  @spec up? :: boolean()
  def up?() do
    :persistent_term.get(:archethic_up, nil) == :up
  end

  @doc """
  Search a transaction by its address
  Check locally and fallback to a quorum read
  """
  @spec search_transaction(address :: binary()) ::
          {:ok, Transaction.t()}
          | {:error, :transaction_not_exists}
          | {:error, :transaction_invalid}
          | {:error, :network_issue}
  def search_transaction(address) when is_binary(address) do
    case TransactionChain.get_transaction(address) do
      {:ok, tx} ->
        {:ok, tx}

      {:error, :invalid_transaction} ->
        {:error, :transaction_invalid}

      {:error, :transaction_not_exists} ->
        storage_nodes =
          Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

        TransactionChain.fetch_transaction_remotely(address, storage_nodes)
    end
  end

  @doc """
  Send a new transaction in the network to be mined. The current node will act as welcome node
  """
  @spec send_new_transaction(Transaction.t()) :: :ok
  def send_new_transaction(
        tx = %Transaction{},
        welcome_node_key \\ Crypto.first_node_public_key()
      ) do
    if P2P.authorized_and_available_node?() do
      case SharedSecrets.verify_synchronization() do
        :ok ->
          do_send_transaction(tx, welcome_node_key)

        :error ->
          forward_transaction(tx, welcome_node_key)

        {:error, last_address_to_sync} ->
          SelfRepair.resync(last_address_to_sync)
          forward_transaction(tx, welcome_node_key)
      end
    else
      # node not authorized
      forward_transaction(tx, welcome_node_key)
    end
  end

  @spec forward_transaction(tx :: Transaction.t(), welcome_node_key :: Crypto.key()) :: :ok
  defp forward_transaction(tx, welcome_node_key) do
    %Node{network_patch: welcome_node_patch} = P2P.get_node_info!(welcome_node_key)

    nodes =
      P2P.authorized_and_available_nodes()
      |> Enum.reject(&(&1.first_public_key == welcome_node_key))
      |> Enum.sort_by(& &1.first_public_key)
      |> P2P.nearest_nodes(welcome_node_patch)
      |> Enum.filter(&Node.locally_available?/1)

    this_node = Crypto.first_node_public_key()

    nodes =
      if this_node != welcome_node_key do
        #  if this node is not the welcome node then select
        # next node from the this node position in nodes list
        index = Enum.find_index(nodes, &(&1.first_public_key == this_node))
        {_l, r} = Enum.split(nodes, index + 1)
        r
      else
        nodes
      end

    TaskSupervisor
    |> Task.Supervisor.start_child(fn ->
      :ok =
        %NewTransaction{transaction: tx, welcome_node: welcome_node_key}
        |> do_forward_transaction(nodes)
    end)

    :ok
  end

  defp do_forward_transaction(msg, [node | rest]) do
    case P2P.send_message(node, msg) do
      {:ok, %Ok{}} ->
        :ok

      {:error, _} ->
        do_forward_transaction(msg, rest)
    end
  end

  defp do_forward_transaction(_, []), do: {:error, :network_issue}

  defp do_send_transaction(tx = %Transaction{type: tx_type}, welcome_node_key) do
    current_date = DateTime.utc_now()
    sorting_seed = Election.validation_nodes_election_seed_sorting(tx, current_date)

    # We are selecting only the authorized nodes the current date of the transaction
    # If new nodes have been authorized, they only will be selected at the application date
    node_list = P2P.authorized_and_available_nodes(current_date)

    storage_nodes = Election.chain_storage_nodes(tx.address, node_list)

    validation_nodes =
      Election.validation_nodes(
        tx,
        sorting_seed,
        node_list,
        storage_nodes,
        Election.get_validation_constraints()
      )

    message = %StartMining{
      transaction: tx,
      welcome_node_public_key: get_welcome_node_public_key(tx_type, welcome_node_key),
      validation_node_public_keys: Enum.map(validation_nodes, & &1.last_public_key)
    }

    P2P.broadcast_message(validation_nodes, message)
  end

  # Since welcome node is not anymore constant, as we want unauthorised
  # nodes to do some labor. Following bootstrapping, the txn of a new node
  # is sent, with the welcome node being the same new node whose information
  # does not exist in the network. Thus solitary and distributed workflows
  # are more susceptible to failures.
  defp get_welcome_node_public_key(:node, key) do
    case P2P.get_node_info(key) do
      {:error, _} ->
        Crypto.last_node_public_key()

      _ ->
        key
    end
  end

  defp get_welcome_node_public_key(_, key), do: key

  @doc """
  Retrieve the last transaction for a chain from the closest nodes
  """
  @spec get_last_transaction(address :: binary()) ::
          {:ok, Transaction.t()}
          | {:error, :transaction_not_exists}
          | {:error, :transaction_invalid}
          | {:error, :network_issue}
  def get_last_transaction(address) when is_binary(address) do
    case get_last_transaction_address(address) do
      {:ok, last_address} ->
        search_transaction(last_address)

      {:error, :network_issue} = e ->
        e
    end
  end

  @doc """
  Retrieve the last transaction address for a chain from the closest nodes
  """
  @spec get_last_transaction_address(address :: binary()) ::
          {:ok, binary()}
          | {:error, :network_issue}
  def get_last_transaction_address(address) when is_binary(address) do
    TransactionChain.resolve_last_address(address)
  end

  @doc """
  Retrieve the balance from an address from the closest nodes
  """
  @spec get_balance(binary) :: {:ok, Account.balance()} | {:error, :network_issue}
  def get_balance(address) when is_binary(address) do
    address
    |> Election.chain_storage_nodes(P2P.authorized_and_available_nodes())
    |> get_balance(address)
  end

  defp get_balance(nodes, address) do
    case P2P.quorum_read(nodes, %GetBalance{address: address}, &balance_conflict_resolver/1) do
      {:ok, %Balance{uco: uco, token: token}} -> {:ok, %{uco: uco, token: token}}
      error -> error
    end
  end

  defp balance_conflict_resolver(balances) do
    {max_uco, max_token} =
      balances
      |> Enum.reduce({0, %{}}, fn
        %Balance{uco: uco, token: token}, {uco_acc, token_acc} ->
          token_merger = fn _k, v1, v2 -> max(v1, v2) end

          maximum_token = Map.merge(token, token_acc, token_merger)
          maximum_uco = max(uco, uco_acc)

          {maximum_uco, maximum_token}
      end)

    %{uco: max_uco, token: max_token}
  end

  @doc """
  Request to fetch the inputs for a transaction address from the closest nodes
  """
  @spec get_transaction_inputs(binary()) :: list(TransactionInput.t())
  def get_transaction_inputs(address) when is_binary(address) do
    # check the last transaction inputs to determine if a utxo is spent or not
    {:ok, latest_address} = get_last_transaction_address(address)

    if latest_address == address do
      do_get_transaction_inputs(address)
    else
      latest_tx_inputs = do_get_transaction_inputs(latest_address)
      current_tx_inputs = do_get_transaction_inputs(address)

      Enum.map(current_tx_inputs, fn input ->
        spent? =
          not Enum.any?(latest_tx_inputs, fn input2 ->
            input.from == input2.from and input.type == input2.type
          end)

        %TransactionInput{input | spent?: spent?}
      end)
    end
  end

  defp do_get_transaction_inputs(address) do
    nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

    address
    |> TransactionChain.stream_inputs_remotely(nodes, DateTime.utc_now())
    |> Enum.to_list()
  end

  @doc """
  Request to fetch the inputs for a transaction address from the closest nodes at a given page
  """
  @spec get_transaction_inputs(
          binary(),
          paging_offset :: non_neg_integer(),
          limit :: non_neg_integer()
        ) :: list(TransactionInput.t())
  def get_transaction_inputs(address, page, limit)
      when is_binary(address) and is_integer(page) and page >= 0 and is_integer(limit) and
             limit >= 0 do
    nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

    {inputs, _more?, _offset} =
      TransactionChain.fetch_inputs_remotely(address, nodes, DateTime.utc_now(), page, limit)

    inputs
  end

  @doc """
  Retrieve a transaction chain based on an address from the closest nodes
  by setting `paging_address as an offset address.
  """
  @spec get_transaction_chain_by_paging_address(binary(), binary() | nil, :asc | :desc) ::
          {:ok, list(Transaction.t())} | {:error, :network_issue}
  def get_transaction_chain_by_paging_address(address, paging_address, :asc)
      when is_binary(address) do
    case get_last_transaction_address(address) do
      {:ok, last_address} ->
        with {local_chain, false, _} <-
               TransactionChain.get(address, [], paging_state: paging_address, order: :asc),
             %Transaction{address: ^last_address} <- List.last(local_chain) do
          {:ok, local_chain}
        else
          {local_chain, true, _} ->
            # Local chain already contains 10 transactions
            {:ok, local_chain}

          _ ->
            last_address
            |> Election.chain_storage_nodes(P2P.authorized_and_available_nodes())
            |> TransactionChain.fetch_transaction_chain(last_address, paging_address, order: :asc)
        end

      error ->
        error
    end
  end

  def get_transaction_chain_by_paging_address(address, paging_address, :desc)
      when is_binary(address) do
    case get_last_transaction_address(address) do
      {:ok, last_address} ->
        if TransactionChain.transaction_exists?(last_address) do
          {chain, _, _} =
            TransactionChain.get(address, [], paging_state: paging_address, order: :desc)

          {:ok, chain}
        else
          last_address
          |> Election.chain_storage_nodes(P2P.authorized_and_available_nodes())
          |> TransactionChain.fetch_transaction_chain(address, paging_address, order: :desc)
        end

      error ->
        error
    end
  end

  @doc """
  Parse the given transaction and return a contract if successful
  """
  @spec parse_contract(Transaction.t()) :: {:ok, Contract.t()} | {:error, String.t()}
  defdelegate parse_contract(contract_tx),
    to: Interpreter,
    as: :parse_transaction

  @doc """
  Execute the contract in the given transaction.
  We assume the contract is parse-able.
  """
  @spec execute_contract(
          Contract.trigger_type(),
          Contract.t(),
          nil | Transaction.t()
        ) ::
          {:ok, nil | Transaction.t()}
          | {:error,
             :contract_failure
             | :invalid_triggers_execution
             | :invalid_transaction_constraints
             | :invalid_oracle_constraints
             | :invalid_inherit_constraints}
  defdelegate execute_contract(trigger_type, contract, maybe_tx),
    to: Interpreter,
    as: :execute

  @doc """
  Retrieve the number of transaction in a transaction chain from the closest nodes
  """
  @spec get_transaction_chain_length(binary()) ::
          {:ok, non_neg_integer()} | {:error, :network_issue}
  def get_transaction_chain_length(address) when is_binary(address) do
    case get_last_transaction_address(address) do
      {:ok, last_address} ->
        nodes = Election.chain_storage_nodes(last_address, P2P.authorized_and_available_nodes())
        TransactionChain.fetch_size_remotely(address, nodes)

      error ->
        error
    end
  end

  @doc """
  Fetch a summaries aggregate for a given date.
  Check locally first and fallback to a quorum read
  """
  @spec fetch_summaries_aggregate(DateTime.t()) ::
          {:ok, BeaconChain.SummaryAggregate.t()} | {:error, atom()}
  def fetch_summaries_aggregate(date) do
    case BeaconChain.get_summaries_aggregate(date) do
      {:error, :not_exists} ->
        nodes = P2P.authorized_and_available_nodes()
        BeaconChain.fetch_summaries_aggregate(date, nodes)

      {:ok, aggregate} ->
        {:ok, aggregate}
    end
  end

  @doc """
  Request from the beacon chains all the summaries for the given dates and aggregate them
  """
  @spec fetch_and_aggregate_summaries(DateTime.t()) :: BeaconChain.SummaryAggregate.t()
  def fetch_and_aggregate_summaries(date) do
    BeaconChain.fetch_and_aggregate_summaries(date, P2P.authorized_and_available_nodes())
  end

  @doc """
  Retrieve the genesis address locally or remotely
  """
  def fetch_genesis_address_remotely(address) do
    case TransactionChain.get_genesis_address(address) do
      ^address ->
        # if returned address is same as given, it means the DB does not contain the value
        nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

        TransactionChain.fetch_genesis_address_remotely(address, nodes)

      genesis_address ->
        {:ok, genesis_address}
    end
  end

  defdelegate list_transactions_summaries_from_current_slot(),
    to: BeaconChain

  defdelegate list_transactions_summaries_from_current_slot(date),
    to: BeaconChain

  @doc """
  Check if a transaction exists at address
  Check locally first and fallback to a quorum read
  """
  @spec transaction_exists?(binary()) :: boolean()
  def transaction_exists?(address) do
    if TransactionChain.transaction_exists?(address) do
      # if it exists locally, no need to query the network
      true
    else
      storage_nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

      conflict_resolver = fn results ->
        # Prioritize transactions results over not found
        case Enum.filter(results, &match?(%TransactionSummaryMessage{}, &1)) do
          [] ->
            %NotFound{}

          [%{transaction_summary: first} | _] ->
            first
        end
      end

      case P2P.quorum_read(
             storage_nodes,
             %GetTransactionSummary{address: address},
             conflict_resolver
           ) do
        {:ok, %TransactionSummary{address: ^address}} ->
          true

        {:ok, %NotFound{}} ->
          false

        {:error, e} ->
          raise e
      end
    end
  end
end
