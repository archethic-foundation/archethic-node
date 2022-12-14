defmodule Archethic do
  @moduledoc """
  Provides high level functions serving the API and the Explorer
  """

  alias __MODULE__.Account
  alias __MODULE__.BeaconChain
  alias __MODULE__.Crypto

  alias __MODULE__.Election

  alias __MODULE__.P2P
  alias __MODULE__.P2P.Node

  alias __MODULE__.P2P.Message.Balance
  alias __MODULE__.P2P.Message.GetBalance
  alias __MODULE__.P2P.Message.NewTransaction
  alias __MODULE__.P2P.Message.Ok
  alias __MODULE__.P2P.Message.StartMining

  alias __MODULE__.TransactionChain
  alias __MODULE__.TransactionChain.Transaction
  alias __MODULE__.TransactionChain.TransactionInput

  require Logger

  @doc """
  Query the search of the transaction to the dedicated storage pool from the closest nodes
  """
  @spec search_transaction(address :: binary()) ::
          {:ok, Transaction.t()}
          | {:error, :transaction_not_exists}
          | {:error, :transaction_invalid}
          | {:error, :network_issue}
  def search_transaction(address) when is_binary(address) do
    storage_nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())
    TransactionChain.fetch_transaction_remotely(address, storage_nodes)
  end

  @doc """
  Send a new transaction in the network to be mined. The current node will act as welcome node
  """
  @spec send_new_transaction(Transaction.t()) :: :ok | {:error, :network_issue}
  def send_new_transaction(
        tx = %Transaction{},
        welcome_node_key \\ Crypto.first_node_public_key()
      ) do
    if P2P.authorized_and_available_node?() do
      do_send_transaction(tx, welcome_node_key)
    else
      P2P.authorized_and_available_nodes()
      |> Enum.filter(&Node.locally_available?/1)
      |> P2P.nearest_nodes()
      |> forward_transaction(tx)
    end
  end

  defp forward_transaction([node | rest], tx) do
    case P2P.send_message(node, %NewTransaction{transaction: tx}) do
      {:ok, %Ok{}} ->
        :ok

      {:error, _} ->
        forward_transaction(rest, tx)
    end
  end

  defp forward_transaction([], _), do: {:error, :network_issue}

  defp do_send_transaction(tx = %Transaction{type: tx_type}, welcome_node_key) do
    current_date = DateTime.utc_now()
    sorting_seed = Election.validation_nodes_election_seed_sorting(tx, current_date)

    # We are selecting only the authorized nodes the current date of the transaction
    # If new nodes have been authorized, they only will be selected at the application date
    node_list = P2P.authorized_and_available_nodes(current_date)

    storage_nodes = Election.chain_storage_nodes_with_type(tx.address, tx.type, node_list)

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
        nodes = Election.chain_storage_nodes(last_address, P2P.authorized_and_available_nodes())
        TransactionChain.fetch_transaction_remotely(last_address, nodes)

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
  Retrieve a transaction chain based on an address from the closest nodes.
  """
  @spec get_transaction_chain(binary()) :: {:ok, list(Transaction.t())} | {:error, :network_issue}
  def get_transaction_chain(address) when is_binary(address) do
    nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

    # We directly check if the transaction exists and retrieve the genesis
    # Otherwise we are requesting the genesis address remotly
    genesis_address =
      with ^address <- TransactionChain.get_genesis_address(address),
           {:ok, genesis_address} <- TransactionChain.fetch_genesis_address_remotely(address) do
        genesis_address
      else
        _ ->
          address
      end

    %{transactions: local_chain, last_address: last_local_address} =
      genesis_address
      |> TransactionChain.scan_chain(address)
      |> Enum.reduce_while(%{transactions: [], last_address: nil}, fn transaction, acc ->
        # We stop at the desire the transaction
        if acc.last_address == address do
          {:halt, acc}
        else
          new_acc =
            acc
            |> Map.update!(:transactions, &(&1 ++ [transaction]))
            # We log the last local address
            |> Map.put(:last_address, transaction.address)

          {:cont, new_acc}
        end
      end)

    remote_chain =
      if address != last_local_address do
        address
        |> TransactionChain.stream_remotely(nodes, last_local_address)
        |> Stream.flat_map(& &1)
        |> Enum.to_list()
      else
        []
      end

    {:ok, local_chain ++ remote_chain}
  end

  @doc """
  Retrieve a transaction chain based on an address from the closest nodes
  by setting `paging_address as an offset address.
  """
  @spec get_transaction_chain_by_paging_address(binary(), binary()) ::
          {:ok, list(Transaction.t())} | {:error, :network_issue}
  def get_transaction_chain_by_paging_address(address, paging_address) when is_binary(address) do
    nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

    try do
      {local_chain, paging_address} =
        with true <- paging_address != nil,
             true <- TransactionChain.transaction_exists?(paging_address),
             last_address when last_address != nil <-
               TransactionChain.get_last_local_address(address),
             true <- last_address != paging_address do
          {TransactionChain.get_locally(last_address, paging_address), last_address}
        else
          _ -> {[], paging_address}
        end

      remote_chain =
        if paging_address != address do
          case TransactionChain.fetch_transaction_chain(nodes, address, paging_address) do
            {:ok, transactions} -> transactions
            {:error, _} -> []
          end
        else
          []
        end

      {:ok, local_chain ++ remote_chain}
    catch
      _ ->
        {:error, :network_issue}
    end
  end

  @doc """
  Retrieve the number of transaction in a transaction chain from the closest nodes
  """
  @spec get_transaction_chain_length(binary()) ::
          {:ok, non_neg_integer()} | {:error, :network_issue}
  def get_transaction_chain_length(address) when is_binary(address) do
    nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())
    TransactionChain.fetch_size_remotely(address, nodes)
  end

  @doc """
  Fetch a summaries aggregate for a given date.
  If node is a storage node, it will skip I/O and fetch from local DB
  """
  @spec fetch_summaries_aggregate(DateTime.t()) ::
          {:ok, BeaconChain.SummaryAggregate.t()} | {:error, atom()}
  def fetch_summaries_aggregate(date) do
    nodes = P2P.authorized_and_available_nodes()

    is_a_beacon_storage_node? =
      date
      |> Crypto.derive_beacon_aggregate_address()
      |> Election.beacon_storage_node?(date, Crypto.first_node_public_key(), nodes)

    if is_a_beacon_storage_node? do
      BeaconChain.get_summaries_aggregate(date)
    else
      BeaconChain.fetch_summaries_aggregate(date, nodes)
    end
  end

  @doc """
  Request from the beacon chains all the summaries for the given dates and aggregate them
  """
  @spec fetch_and_aggregate_summaries(DateTime.t()) :: BeaconChain.SummaryAggregate.t()
  def fetch_and_aggregate_summaries(date) do
    BeaconChain.fetch_and_aggregate_summaries(date, P2P.authorized_and_available_nodes())
  end
end
