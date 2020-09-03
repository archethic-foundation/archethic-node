defmodule Uniris do
  @moduledoc """
  Provides high level functions serving the API and the Explorer
  """
  alias __MODULE__.Crypto
  alias __MODULE__.Election

  alias __MODULE__.P2P
  alias __MODULE__.P2P.Node

  alias __MODULE__.P2P.Message.Balance
  alias __MODULE__.P2P.Message.GetBalance
  alias __MODULE__.P2P.Message.GetLastTransaction
  alias __MODULE__.P2P.Message.GetTransaction
  alias __MODULE__.P2P.Message.GetTransactionChain
  alias __MODULE__.P2P.Message.GetTransactionChainLength
  alias __MODULE__.P2P.Message.GetTransactionInputs
  alias __MODULE__.P2P.Message.NotFound
  alias __MODULE__.P2P.Message.StartMining
  alias __MODULE__.P2P.Message.TransactionInputList
  alias __MODULE__.P2P.Message.TransactionList

  alias __MODULE__.Storage
  alias __MODULE__.Storage.Memory.ChainLookup
  alias __MODULE__.Storage.Memory.UCOLedger

  alias __MODULE__.Transaction
  alias __MODULE__.TransactionInput

  @doc """
  Query the search of the transaction to the dedicated storage pool
  """
  @spec search_transaction(address :: binary()) ::
          {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  def search_transaction(address) when is_binary(address) do
    case Storage.get_transaction(address) do
      {:ok, tx} ->
        {:ok, tx}

      _ ->
        {:ok, %Node{network_patch: patch}} = P2P.node_info()

        address
        |> Election.storage_nodes()
        |> P2P.nearest_nodes(patch)
        |> List.first()
        |> P2P.send_message(%GetTransaction{address: address})
        |> case do
          tx = %Transaction{} ->
            {:ok, tx}

          %NotFound{} ->
            {:error, :transaction_not_exists}
        end
    end
  end

  @doc """
  Send a new transaction in the network to be mined. The current node will act as welcome node
  """
  @spec send_new_transaction(Transaction.t()) :: :ok
  def send_new_transaction(tx = %Transaction{}) do
    validation_nodes = Election.validation_nodes(tx)

    Enum.each(validation_nodes, fn node ->
      Task.start(fn ->
        P2P.send_message(
          node,
          %StartMining{
            transaction: tx,
            welcome_node_public_key: Crypto.node_public_key(),
            validation_node_public_keys: Enum.map(validation_nodes, & &1.last_public_key)
          }
        )
      end)
    end)
  end

  @spec get_last_transaction(address :: binary()) ::
          {:ok, Transaction.t()} | {:error, :not_found}
  def get_last_transaction(address) do
    case ChainLookup.get_last_transaction_address(address) do
      {:ok, last_address} ->
        search_transaction(last_address)

      {:error, :not_found} ->
        {:ok, %Node{network_patch: patch}} = P2P.node_info()

        address
        |> Election.storage_nodes()
        |> P2P.nearest_nodes(patch)
        |> List.first()
        |> P2P.send_message(%GetLastTransaction{address: address})
        |> case do
          %NotFound{} ->
            {:error, :not_found}

          tx = %Transaction{} ->
            {:ok, tx}
        end
    end
  end

  @doc """
  Retrieve the balance from an address.

  If the current node is a storage of this address, it will perform a fast lookup
  Otherwise it will request the closest storage node about it
  """
  @spec get_balance(binary) :: uco_balance :: float()
  def get_balance(address) do
    storage_nodes = Election.storage_nodes(address)

    if Crypto.node_public_key(0) in Enum.map(storage_nodes, & &1.first_public_key) do
      UCOLedger.balance(address)
    else
      {:ok, %Node{network_patch: patch}} = P2P.node_info()

      %Balance{uco: uco_balance} =
        storage_nodes
        |> P2P.nearest_nodes(patch)
        |> List.first()
        |> P2P.send_message(%GetBalance{address: address})

      uco_balance
    end
  end

  @doc """
  Request to fetch the inputs for a transaction address
  """
  @spec get_transaction_inputs(Crypto.key()) :: list(TransactionInput.t())
  def get_transaction_inputs(address) do
    storage_nodes = Election.storage_nodes(address)

    if Crypto.node_public_key(0) in Enum.map(storage_nodes, & &1.first_public_key) do
      UCOLedger.get_inputs(address)
    else
      {:ok, %Node{network_patch: patch}} = P2P.node_info()

      %TransactionInputList{inputs: inputs} =
        storage_nodes
        |> P2P.nearest_nodes(patch)
        |> List.first()
        |> P2P.send_message(%GetTransactionInputs{address: address})

      inputs
    end
  end

  @doc """
  Retrieve a transaction chain based on an address
  """
  @spec get_transaction_chain(binary()) :: list(Transaction.t())
  def get_transaction_chain(address) do
    storage_nodes = Election.storage_nodes(address)

    if Crypto.node_public_key(0) in Enum.map(storage_nodes, & &1.first_public_key) do
      Storage.get_transaction_chain(address)
    else
      {:ok, %Node{network_patch: patch}} = P2P.node_info()

      %TransactionList{transactions: chain} =
        storage_nodes
        |> P2P.nearest_nodes(patch)
        |> List.first()
        |> P2P.send_message(%GetTransactionChain{address: address})

      chain
    end
  end

  @doc """
  Retrieve the number of transaction in a transaction chain
  """
  @spec get_transaction_chain_length(binary()) :: non_neg_integer()
  def get_transaction_chain_length(address) do
    storage_nodes = Election.storage_nodes(address)

    if Crypto.node_public_key(0) in Enum.map(storage_nodes, & &1.first_public_key) do
      ChainLookup.get_transaction_chain_length(address)
    else
      {:ok, %Node{network_patch: patch}} = P2P.node_info()

      %TransactionList{transactions: chain} =
        storage_nodes
        |> P2P.nearest_nodes(patch)
        |> List.first()
        |> P2P.send_message(%GetTransactionChainLength{address: address})

      chain
    end
  end
end
