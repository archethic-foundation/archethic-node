defmodule Archethic do
  @moduledoc """
  Provides high level functions serving the API and the Explorer
  """

  alias __MODULE__.Account
  alias __MODULE__.Crypto

  alias __MODULE__.Election

  alias __MODULE__.Mining

  alias __MODULE__.P2P

  alias __MODULE__.DB

  alias __MODULE__.P2P.Message.Balance
  alias __MODULE__.P2P.Message.GetBalance
  alias __MODULE__.P2P.Message.NewTransaction
  alias __MODULE__.P2P.Message.Ok
  alias __MODULE__.P2P.Message.StartMining
  alias __MODULE__.P2P.Node

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

    nodes =
      storage_nodes
      |> P2P.nearest_nodes()
      |> Enum.filter(&Node.locally_available?/1)

    TransactionChain.fetch_transaction_remotely(address, nodes)
  end

  @doc """
  Send a new transaction in the network to be mined. The current node will act as welcome node
  """
  @spec send_new_transaction(Transaction.t()) :: :ok | {:error, :network_issue}
  def send_new_transaction(tx = %Transaction{}) do
    if P2P.authorized_node?() do
      do_send_transaction(tx)
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

  defp do_send_transaction(tx) do
    current_date = DateTime.utc_now()
    sorting_seed = Election.validation_nodes_election_seed_sorting(tx, current_date)

    # We are selecting only the authorized nodes the current date of the transaction
    # If new nodes have been authorized, they only will be selected at the application date
    node_list = Mining.transaction_validation_node_list(current_date)

    storage_nodes = Election.chain_storage_nodes_with_type(tx.address, tx.type, node_list)

    validation_nodes =
      Election.validation_nodes(
        tx,
        sorting_seed,
        node_list,
        storage_nodes,
        Election.get_validation_constraints()
      )
      # We reject the unavailable nodes for the mining notification
      # but not for the election to avoid any issue in the future
      # during the verification
      |> Enum.filter(& &1.available?)

    message = %StartMining{
      transaction: tx,
      welcome_node_public_key: Crypto.last_node_public_key(),
      validation_node_public_keys: Enum.map(validation_nodes, & &1.last_public_key)
    }

    P2P.broadcast_message(validation_nodes, message)
  end

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
        nodes =
          last_address
          |> Election.chain_storage_nodes(P2P.authorized_and_available_nodes())
          |> P2P.nearest_nodes()
          |> Enum.filter(&Node.locally_available?/1)

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
    |> P2P.nearest_nodes()
    |> Enum.filter(&Node.locally_available?/1)
    |> get_balance(address)
  end

  defp get_balance([node | rest], address) do
    case P2P.send_message(node, %GetBalance{address: address}) do
      {:ok, %Balance{uco: uco, token: token}} ->
        {:ok, %{uco: uco, token: token}}

      {:error, _} ->
        get_balance(rest, address)
    end
  end

  defp get_balance([], _), do: {:error, :network_issue}

  @doc """
  Request to fetch the inputs for a transaction address from the closest nodes
  """
  @spec get_transaction_inputs(binary()) ::
          {:ok, list(TransactionInput.t())} | {:error, :network_issue}
  def get_transaction_inputs(address) when is_binary(address) do
    nodes =
      address
      |> Election.chain_storage_nodes(P2P.authorized_and_available_nodes())
      |> P2P.nearest_nodes()
      |> Enum.filter(&Node.locally_available?/1)

    TransactionChain.fetch_inputs_remotely(address, nodes, DateTime.utc_now())
  end

  @doc """
  Retrieve a transaction chain based on an address from the closest nodes.
  """
  @spec get_transaction_chain(binary()) :: {:ok, list(Transaction.t())} | {:error, :network_issue}
  def get_transaction_chain(address) when is_binary(address) do
    nodes =
      address
      |> Election.chain_storage_nodes(P2P.authorized_and_available_nodes())
      |> P2P.nearest_nodes()
      |> Enum.filter(&Node.locally_available?/1)

    try do
      {local_chain, paging_address} =
        case TransactionChain.get_last_local_address(address) do
          nil -> {[], nil}
          last_address -> {TransactionChain.get_locally(last_address), last_address}
        end

      remote_chain =
        if address != paging_address do
          address
          |> TransactionChain.stream_remotely(nodes, paging_address)
          |> Enum.to_list()
          |> List.flatten()
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
  Retrieve a transaction chain based on an address from the closest nodes
  by setting `paging_address as an offset address.
  """
  @spec get_transaction_chain_by_paging_address(binary(), binary()) ::
          {:ok, list(Transaction.t())} | {:error, :network_issue}
  def get_transaction_chain_by_paging_address(address, paging_address) when is_binary(address) do
    nodes =
      address
      |> Election.chain_storage_nodes(P2P.authorized_and_available_nodes())
      |> P2P.nearest_nodes()
      |> Enum.filter(&Node.locally_available?/1)

    try do
      {local_chain, paging_address} =
        with true <- paging_address != nil,
             true <- DB.transaction_exists?(paging_address),
             last_address when last_address != nil <-
               TransactionChain.get_last_local_address(address),
             true <- last_address != paging_address do
          {TransactionChain.get_locally(last_address, paging_address), last_address}
        else
          _ -> {[], paging_address}
        end

      remote_chain =
        if paging_address != address do
          address
          |> TransactionChain.stream_remotely(nodes, paging_address)
          |> Enum.to_list()
          |> List.flatten()
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
    nodes =
      address
      |> Election.chain_storage_nodes(P2P.authorized_and_available_nodes())
      |> P2P.nearest_nodes()
      |> Enum.filter(&Node.locally_available?/1)

    TransactionChain.fetch_size_remotely(address, nodes)
  end
end
