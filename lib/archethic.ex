defmodule Archethic do
  @moduledoc """
  Provides high level functions serving the API and the Explorer
  """

  alias Archethic.Account
  alias Archethic.BeaconChain
  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.Mining
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message

  alias Archethic.P2P.Message.{
    Balance,
    Error,
    GetBalance,
    NewTransaction,
    Ok,
    StartMining,
    ValidationError
  }

  alias Archethic.SelfRepair
  alias Archethic.SelfRepair.NetworkChain
  alias Archethic.SelfRepair.NetworkView
  alias Archethic.TaskSupervisor
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
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
  @spec send_new_transaction(Transaction.t(), opts :: Keyword.t()) :: :ok
  def send_new_transaction(tx = %Transaction{address: address, type: type}, opts \\ []) do
    welcome_node_key = Keyword.get(opts, :welcome_node_key, Crypto.first_node_public_key())
    contract_context = Keyword.get(opts, :contract_context, nil)
    forward? = Keyword.get(opts, :forward?, false)

    cond do
      P2P.authorized_and_available_node?() and shared_secret_synced?() ->
        validation_nodes = Mining.get_validation_nodes(tx)

        responses =
          %{already_locked?: already_locked?} =
          do_send_transaction(tx, validation_nodes, welcome_node_key, contract_context)

        maybe_start_resync(responses)

        if forward? and not enough_ack?(responses, length(validation_nodes)),
          do: forward_transaction(tx, welcome_node_key, contract_context)

        if already_locked?, do: notify_welcome_node(welcome_node_key, address, :already_locked)

      forward? ->
        forward_transaction(tx, welcome_node_key, contract_context)

      true ->
        Logger.debug("Transaction has not been forwarded",
          transaction_address: Base.encode16(address),
          transaction_type: type
        )
    end

    :ok
  end

  defp shared_secret_synced?() do
    case NetworkChain.verify_synchronization(:node_shared_secrets) do
      :ok ->
        true

      {:error, [{genesis_address, address}]} ->
        SelfRepair.resync(genesis_address, [address], [])
        false

      :error ->
        false
    end
  end

  defp do_send_transaction(
         tx = %Transaction{type: tx_type},
         validation_nodes,
         welcome_node_key,
         contract_context
       ) do
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
        p2p_resync_needed: false,
        already_locked?: false
      },
      &reduce_start_mining_responses/2
    )
  end

  defp forward_transaction(
         tx = %Transaction{address: address, type: type},
         welcome_node_key,
         contract_context
       ) do
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
      message = %NewTransaction{
        transaction: tx,
        welcome_node: welcome_node_key,
        contract_context: contract_context
      }

      case do_forward_transaction(message, nodes) do
        {:error, _} ->
          Logger.warning("Forward transaction did not succeed",
            transaction_address: Base.encode16(address),
            transaction_type: type
          )

        _ ->
          :ok
      end
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

  defp reduce_start_mining_responses({:ok, %Error{reason: :already_locked}}, acc) do
    # In this case we don't want to forward transaction since one is already being valided.
    # But we want to notify user that this new transaction is not being mined
    %{acc | ok: acc.ok + 1, already_locked?: true}
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

  defp enough_ack?(_, 1), do: true
  defp enough_ack?(%{ok: ok_count}, _), do: ok_count >= 2

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

  defp notify_welcome_node(welcome_node_key, address, :already_locked) do
    Task.Supervisor.start_child(TaskSupervisor, fn ->
      message = %ValidationError{
        context: :invalid_transaction,
        reason: "Transaction already in mining with different data",
        address: address
      }

      P2P.send_message(welcome_node_key, message)
    end)

    :ok
  end

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
  Request to fetch the unspent outputs for a transaction address from the closest nodes
  """
  @spec get_unspent_outputs(address :: Crypto.prepended_hash(), genesis? :: boolean()) ::
          list(UnspentOutput.t())
  def get_unspent_outputs(address, genesis? \\ false) do
    nodes = Election.storage_nodes(address, P2P.authorized_and_available_nodes())
    TransactionChain.fetch_unspent_outputs(address, nodes, genesis?) |> Enum.to_list()
  end

  @doc """
  Retrieve a transaction chain based on an address from the closest nodes
  by setting paging_state as an offset address or a date.
  """
  @spec get_pagined_transaction_chain(
          address :: Crypto.prepended_hash(),
          paging_state :: Crypto.prepended_hash() | DateTime.t() | nil,
          order :: :asc | :desc
        ) ::
          {:ok, list(Transaction.t())} | {:error, :network_issue}
  def get_pagined_transaction_chain(address, paging_state, order) do
    case get_last_transaction_address(address) do
      {:ok, last_address} ->
        storage_nodes =
          Election.chain_storage_nodes(last_address, P2P.authorized_and_available_nodes())

        transactions =
          TransactionChain.fetch(last_address, storage_nodes,
            paging_state: paging_state,
            order: order
          )
          |> Enum.take(10)

        {:ok, transactions}

      error ->
        error
    end
  end

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
