defmodule Archethic do
  @moduledoc """
  Provides high level functions serving the API and the Explorer
  """

  alias Archethic.Account
  alias Archethic.BeaconChain
  alias Archethic.Contracts
  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Interpreter
  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message

  alias Archethic.P2P.Message.{
    Balance,
    Error,
    GetBalance,
    NewTransaction,
    Ok,
    StartMining
  }

  alias Archethic.SelfRepair
  alias Archethic.SelfRepair.NetworkChain
  alias Archethic.SelfRepair.NetworkView
  alias Archethic.SharedSecrets
  alias Archethic.TaskSupervisor
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionInput

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
          | {:error, :invalid_transaction}
          | {:error, :network_issue}
  def search_transaction(address) when is_binary(address) do
    storage_nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

    TransactionChain.fetch_transaction(address, storage_nodes)
  end

  @doc """
  Send a new transaction in the network to be mined. The current node will act as welcome node
  """
  @spec send_new_transaction(Transaction.t(), Crypto.key(), nil | Contract.Context.t()) :: :ok
  def send_new_transaction(
        tx = %Transaction{},
        welcome_node_key \\ Crypto.first_node_public_key(),
        contract_context \\ nil
      ) do
    if P2P.authorized_and_available_node?() do
      case NetworkChain.verify_synchronization(:node_shared_secrets) do
        :ok ->
          do_send_transaction(tx, welcome_node_key, contract_context)

        :error ->
          forward_transaction(tx, welcome_node_key, contract_context)

        {:error, addresses} ->
          SharedSecrets.genesis_address(:node_shared_secrets) |> SelfRepair.resync(addresses, [])

          forward_transaction(tx, welcome_node_key, contract_context)
      end
    else
      # node not authorized
      forward_transaction(tx, welcome_node_key, contract_context)
    end
  end

  @spec forward_transaction(
          tx :: Transaction.t(),
          welcome_node_key :: Crypto.key(),
          contract_context :: Contract.Context.t()
        ) :: :ok
  defp forward_transaction(tx, welcome_node_key, contract_context) do
    %Node{network_patch: welcome_node_patch} = P2P.get_node_info!(welcome_node_key)

    nodes =
      P2P.authorized_and_available_nodes()
      |> Enum.reject(&(&1.first_public_key == welcome_node_key))
      |> Enum.sort_by(& &1.first_public_key)
      |> P2P.nearest_nodes(welcome_node_patch)
      |> Enum.filter(&P2P.node_connected?/1)

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
        %NewTransaction{
          transaction: tx,
          welcome_node: welcome_node_key,
          contract_context: contract_context
        }
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

  defp do_send_transaction(tx = %Transaction{type: tx_type}, welcome_node_key, contract_context) do
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
      validation_node_public_keys: Enum.map(validation_nodes, & &1.last_public_key),
      network_chains_view_hash: NetworkView.get_chains_hash(),
      p2p_view_hash: NetworkView.get_p2p_hash(),
      contract_context: contract_context
    }

    Task.Supervisor.async_stream_nolink(
      Archethic.TaskSupervisor,
      validation_nodes,
      &P2P.send_message(&1, message),
      ordered: false,
      on_timeout: :kill_task,
      timeout: Message.get_timeout(message) + 2000
    )
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Stream.map(fn {:ok, res} -> res end)
    |> Enum.reduce(
      %{
        ok: 0,
        network_chains_resync_needed: false,
        p2p_resync_needed: false
      },
      &reduce_start_mining_responses/2
    )
    |> then(fn aggregated_responses ->
      maybe_start_resync(aggregated_responses)

      if should_forward_transaction?(aggregated_responses, length(validation_nodes)) do
        forward_transaction(tx, welcome_node_key, contract_context)
      else
        :ok
      end
    end)
  end

  defp reduce_start_mining_responses({:ok, %Ok{}}, acc) do
    %{acc | ok: acc.ok + 1}
  end

  defp reduce_start_mining_responses({:ok, %Error{reason: :network_chains_sync}}, acc) do
    %{acc | network_chains_resync_needed: true}
  end

  defp reduce_start_mining_responses({:ok, %Error{reason: :p2p_sync}}, acc) do
    %{acc | p2p_resync_needed: true}
  end

  defp reduce_start_mining_responses({:ok, %Error{reason: :both_sync}}, acc) do
    %{acc | network_chains_resync_needed: true, p2p_resync_needed: true}
  end

  defp reduce_start_mining_responses(_, acc) do
    acc
  end

  defp maybe_start_resync(aggregated_responses) do
    if aggregated_responses.network_chains_resync_needed do
      NetworkChain.asynchronous_resync_many([:origin, :oracle, :node_shared_secrets])
    end

    if aggregated_responses.p2p_resync_needed do
      NetworkChain.asynchronous_resync(:node)
    end
  end

  defp should_forward_transaction?(_, 1), do: false
  defp should_forward_transaction?(%{ok: ok_count}, _), do: ok_count < 2

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
          | {:error, :invalid_transaction}
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
    nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

    TransactionChain.fetch_last_address(address, nodes)
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
  @spec get_transaction_inputs(Crypto.prepended_hash(), non_neg_integer(), non_neg_integer()) ::
          list(TransactionInput.t())
  def get_transaction_inputs(address, paging_offset \\ 0, limit \\ 0)
      when is_binary(address) and is_integer(paging_offset) and paging_offset >= 0 and
             is_integer(limit) and limit >= 0 do
    # check the last transaction inputs to determine if a utxo is spent or not
    {:ok, latest_address} = get_last_transaction_address(address)

    if latest_address == address do
      do_get_transaction_inputs(address, paging_offset, limit)
    else
      # TODO: latest inputs can be huge, we should have an other way to determine if a inputs
      # is spent or not
      latest_tx_inputs = do_get_transaction_inputs(latest_address, 0, 0)
      current_tx_inputs = do_get_transaction_inputs(address, paging_offset, limit)

      Enum.map(current_tx_inputs, fn input ->
        spent? =
          not Enum.any?(latest_tx_inputs, fn input2 ->
            input.from == input2.from and input.type == input2.type
          end)

        %TransactionInput{input | spent?: spent?}
      end)
    end
  end

  defp do_get_transaction_inputs(address, paging_offset, limit) do
    nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

    address
    |> TransactionChain.fetch_inputs(nodes, DateTime.utc_now(), paging_offset, limit)
    |> Enum.to_list()
  end

  @doc """
  Retrieve a transaction chain based on an address from the closest nodes
  by setting `paging_address as an offset address.
  """
  @spec get_transaction_chain_by_paging_address(binary(), binary() | nil, :asc | :desc) ::
          {:ok, list(Transaction.t())} | {:error, :network_issue}
  def get_transaction_chain_by_paging_address(address, paging_address, order) do
    case get_last_transaction_address(address) do
      {:ok, last_address} ->
        storage_nodes =
          Election.chain_storage_nodes(last_address, P2P.authorized_and_available_nodes())

        transactions =
          TransactionChain.fetch(last_address, storage_nodes,
            paging_address: paging_address,
            order: order
          )
          |> Enum.take(10)

        {:ok, transactions}

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
  Execute the contract trigger.
  """
  @spec execute_contract(
          Contract.trigger_type(),
          Contract.t(),
          nil | Transaction.t(),
          [Transaction.t()]
        ) ::
          {:ok, nil | Transaction.t()}
          | {:error, :contract_failure | :invalid_triggers_execution}
  defdelegate execute_contract(trigger_type, contract, maybe_trigger_tx, calls),
    to: Contracts,
    as: :execute_trigger

  @doc """
  Retrieve the number of transaction in a transaction chain from the closest nodes
  """
  @spec get_transaction_chain_length(binary()) ::
          {:ok, non_neg_integer()} | {:error, :network_issue}
  def get_transaction_chain_length(address) when is_binary(address) do
    case get_last_transaction_address(address) do
      {:ok, last_address} ->
        nodes = Election.chain_storage_nodes(last_address, P2P.authorized_and_available_nodes())
        TransactionChain.fetch_size(address, nodes)

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
    storage_nodes =
      date
      |> Crypto.derive_beacon_aggregate_address()
      |> Election.chain_storage_nodes(P2P.authorized_and_available_nodes())

    BeaconChain.fetch_summaries_aggregate(date, storage_nodes)
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
  def fetch_genesis_address(address) do
    nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())
    TransactionChain.fetch_genesis_address(address, nodes)
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
    storage_nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())
    TransactionChain.transaction_exists_globally?(address, storage_nodes)
  end
end
