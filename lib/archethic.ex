defmodule ArchEthic do
  @moduledoc """
  Provides high level functions serving the API and the Explorer
  """

  alias __MODULE__.Account
  alias __MODULE__.Crypto

  alias __MODULE__.Election

  alias __MODULE__.Mining

  alias __MODULE__.P2P

  alias __MODULE__.P2P.Message.Balance
  alias __MODULE__.P2P.Message.Error
  alias __MODULE__.P2P.Message.GetBalance
  alias __MODULE__.P2P.Message.GetLastTransaction
  alias __MODULE__.P2P.Message.GetLastTransactionAddress
  alias __MODULE__.P2P.Message.GetTransaction
  alias __MODULE__.P2P.Message.GetTransactionChain
  alias __MODULE__.P2P.Message.GetTransactionChainLength
  alias __MODULE__.P2P.Message.GetTransactionInputs
  alias __MODULE__.P2P.Message.LastTransactionAddress
  alias __MODULE__.P2P.Message.NewTransaction
  alias __MODULE__.P2P.Message.NotFound
  alias __MODULE__.P2P.Message.Ok
  alias __MODULE__.P2P.Message.StartMining
  alias __MODULE__.P2P.Message.TransactionChainLength
  alias __MODULE__.P2P.Message.TransactionInputList
  alias __MODULE__.P2P.Message.TransactionList
  alias __MODULE__.P2P.Node

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
    storage_nodes = Election.chain_storage_nodes(address, P2P.available_nodes())

    storage_nodes
    |> P2P.nearest_nodes()
    |> Enum.filter(&Node.locally_available?/1)
    |> get_transaction(address)
  end

  defp get_transaction([node | rest], address) do
    case P2P.send_message(node, %GetTransaction{address: address}) do
      {:ok, tx = %Transaction{}} ->
        {:ok, tx}

      {:ok, %NotFound{}} ->
        {:error, :transaction_not_exists}

      {:ok, %Error{}} ->
        {:error, :transaction_invalid}

      {:error, _} ->
        get_transaction(rest, address)
    end
  end

  defp get_transaction([], _), do: {:error, :network_issue}

  @doc """
  Send a new transaction in the network to be mined. The current node will act as welcome node
  """
  @spec send_new_transaction(Transaction.t()) :: :ok | {:error, :network_issue}
  def send_new_transaction(tx = %Transaction{}) do
    if P2P.authorized_node?() do
      do_send_transaction(tx)
    else
      P2P.authorized_nodes(DateTime.utc_now())
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
  def get_last_transaction(address) do
    address
    |> Election.chain_storage_nodes(P2P.available_nodes())
    |> P2P.nearest_nodes()
    |> Enum.filter(&Node.locally_available?/1)
    |> get_last_transaction(address)
  end

  defp get_last_transaction([node | rest], address) do
    case P2P.send_message(node, %GetLastTransaction{address: address}) do
      {:ok, tx = %Transaction{}} ->
        {:ok, tx}

      {:ok, %NotFound{}} ->
        {:error, :transaction_not_exists}

      {:ok, %Error{}} ->
        {:error, :transaction_invalid}

      {:error, _} ->
        get_last_transaction(rest, address)
    end
  end

  defp get_last_transaction([], _), do: {:error, :network_issue}

  @doc """
  Retrieve the last transaction address for a chain from the closest nodes
  """
  @spec get_last_transaction_address(address :: binary()) ::
          {:ok, binary()}
          | {:error, :network_issue}
  def get_last_transaction_address(address) do
    address
    |> Election.chain_storage_nodes(P2P.available_nodes())
    |> P2P.nearest_nodes()
    |> Enum.filter(&Node.locally_available?/1)
    |> get_last_transaction_address(address)
  end

  defp get_last_transaction_address([node | rest], address) do
    case P2P.send_message(node, %GetLastTransactionAddress{
           address: address,
           timestamp: DateTime.utc_now()
         }) do
      {:ok, %LastTransactionAddress{address: last_address}} ->
        {:ok, last_address}

      {:error, _} ->
        get_last_transaction_address(rest, address)
    end
  end

  defp get_last_transaction_address([], _), do: {:error, :network_issue}

  @doc """
  Retrieve the balance from an address from the closest nodes
  """
  @spec get_balance(binary) :: {:ok, Account.balance()} | {:error, :network_issue}
  def get_balance(address) when is_binary(address) do
    address
    |> Election.chain_storage_nodes(P2P.available_nodes())
    |> P2P.nearest_nodes()
    |> Enum.filter(&Node.locally_available?/1)
    |> get_balance(address)
  end

  defp get_balance([node | rest], address) do
    case P2P.send_message(node, %GetBalance{address: address}) do
      {:ok, %Balance{uco: uco, nft: nft}} ->
        {:ok, %{uco: uco, nft: nft}}

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
    address
    |> Election.chain_storage_nodes(P2P.available_nodes())
    |> P2P.nearest_nodes()
    |> Enum.filter(&Node.locally_available?/1)
    |> get_transaction_inputs(address)
  end

  defp get_transaction_inputs([node | rest], address) do
    case P2P.send_message(node, %GetTransactionInputs{address: address}) do
      {:ok, %TransactionInputList{inputs: inputs}} ->
        {:ok, inputs}

      {:error, _} ->
        get_transaction_inputs(rest, address)
    end
  end

  defp get_transaction_inputs([], _), do: {:error, :network_issue}

  @doc """
  Retrieve a transaction chain based on an address from the closest nodes
  """
  @spec get_transaction_chain(binary()) :: {:ok, list(Transaction.t())} | {:error, :network_issue}
  def get_transaction_chain(address) when is_binary(address) do
    address
    |> Election.chain_storage_nodes(P2P.available_nodes())
    |> P2P.nearest_nodes()
    |> Enum.filter(&Node.locally_available?/1)
    |> get_transaction_chain(address)
  end

  defp get_transaction_chain([node | rest], address) do
    case P2P.send_message(node, %GetTransactionChain{address: address}) do
      {:ok, %TransactionList{transactions: transactions}} ->
        {:ok, transactions}

      {:error, _} ->
        get_transaction_chain(rest, address)
    end
  end

  defp get_transaction_chain([], _), do: {:error, :network_issue}

  @doc """
  Retrieve the number of transaction in a transaction chain from the closest nodes
  """
  @spec get_transaction_chain_length(binary()) ::
          {:ok, non_neg_integer()} | {:error, :network_issue}
  def get_transaction_chain_length(address) when is_binary(address) do
    address
    |> Election.chain_storage_nodes(P2P.available_nodes())
    |> P2P.nearest_nodes()
    |> Enum.filter(&Node.locally_available?/1)
    |> get_transaction_chain_length(address)
  end

  defp get_transaction_chain_length([node | rest], address) do
    case P2P.send_message(node, %GetTransactionChainLength{address: address}) do
      {:ok, %TransactionChainLength{length: length}} ->
        {:ok, length}

      {:error, _} ->
        get_transaction_chain_length(rest, address)
    end
  end

  defp get_transaction_chain_length([], _), do: {:error, :network_issue}
end
