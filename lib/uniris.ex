defmodule Uniris do
  @moduledoc """
  Provides high level functions serving the API and the Explorer
  """

  alias __MODULE__.Account
  alias __MODULE__.Crypto

  alias __MODULE__.Mining

  alias __MODULE__.P2P

  alias __MODULE__.P2P.Message.Balance
  alias __MODULE__.P2P.Message.GetBalance
  alias __MODULE__.P2P.Message.GetLastTransaction
  alias __MODULE__.P2P.Message.GetTransaction
  alias __MODULE__.P2P.Message.GetTransactionChain
  alias __MODULE__.P2P.Message.GetTransactionChainLength
  alias __MODULE__.P2P.Message.GetTransactionInputs
  alias __MODULE__.P2P.Message.NotFound
  alias __MODULE__.P2P.Message.StartMining
  alias __MODULE__.P2P.Message.TransactionChainLength
  alias __MODULE__.P2P.Message.TransactionInputList
  alias __MODULE__.P2P.Message.TransactionList

  alias __MODULE__.Replication

  alias __MODULE__.TransactionChain
  alias __MODULE__.TransactionChain.Transaction

  alias __MODULE__.Utils

  @doc """
  Query the search of the transaction to the dedicated storage pool
  """
  @spec search_transaction(address :: binary()) ::
          {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  def search_transaction(address) when is_binary(address) do
    storage_nodes =
      address
      |> Replication.chain_storage_nodes(P2P.list_nodes(availability: :global))
      |> P2P.nearest_nodes()

    if Utils.key_in_node_list?(storage_nodes, Crypto.node_public_key(0)) do
      TransactionChain.get_transaction(address)
    else
      response =
        storage_nodes
        |> P2P.broadcast_message(%GetTransaction{address: address})
        |> Enum.at(0)

      case response do
        %NotFound{} ->
          {:error, :transaction_not_exists}

        tx = %Transaction{} ->
          {:ok, tx}
      end
    end
  end

  @doc """
  Send a new transaction in the network to be mined. The current node will act as welcome node
  """
  @spec send_new_transaction(Transaction.t()) :: :ok | {:error, :invalid_transaction}
  def send_new_transaction(tx = %Transaction{}) do
    validation_nodes = Mining.transaction_validation_nodes(tx)

    message = %StartMining{
      transaction: tx,
      welcome_node_public_key: Crypto.node_public_key(),
      validation_node_public_keys: Enum.map(validation_nodes, & &1.last_public_key)
    }

    validation_nodes
    |> P2P.broadcast_message(message)
    |> Stream.run()
  end

  @spec get_last_transaction(address :: binary()) ::
          {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  def get_last_transaction(address) do
    case TransactionChain.get_last_transaction(address) do
      {:ok, tx} ->
        {:ok, tx}

      {:error, :transaction_not_exists} ->
        response =
          address
          |> Replication.chain_storage_nodes(P2P.list_nodes(availability: :global))
          |> P2P.nearest_nodes()
          |> P2P.broadcast_message(%GetLastTransaction{address: address})
          |> Enum.at(0)

        case response do
          %NotFound{} ->
            {:error, :transaction_not_exists}

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
  @spec get_balance(binary) :: Accout.balance()
  def get_balance(address) when is_binary(address) do
    storage_nodes =
      address
      |> Replication.chain_storage_nodes(P2P.list_nodes(availability: :global))
      |> P2P.nearest_nodes()

    if Utils.key_in_node_list?(storage_nodes, Crypto.node_public_key(0)) do
      Account.get_balance(address)
    else
      %Balance{uco: uco_balance, nft: nft_balances} =
        storage_nodes
        |> P2P.broadcast_message(%GetBalance{address: address})
        |> Enum.at(0)

      %{uco: uco_balance, nft: nft_balances}
    end
  end

  @doc """
  Request to fetch the inputs for a transaction address
  """
  @spec get_transaction_inputs(Crypto.key()) :: list(Input.t())
  def get_transaction_inputs(address) do
    storage_nodes =
      address
      |> Replication.chain_storage_nodes(P2P.list_nodes(availability: :global))
      |> P2P.nearest_nodes()

    if Utils.key_in_node_list?(storage_nodes, Crypto.node_public_key(0)) do
      Account.get_inputs(address)
    else
      %TransactionInputList{inputs: inputs} =
        storage_nodes
        |> P2P.broadcast_message(%GetTransactionInputs{address: address})
        |> Enum.at(0)

      inputs
    end
  end

  @doc """
  Retrieve a transaction chain based on an address
  """
  @spec get_transaction_chain(binary()) :: list(Transaction.t())
  def get_transaction_chain(address) do
    storage_nodes =
      address
      |> Replication.chain_storage_nodes(P2P.list_nodes(availability: :global))
      |> P2P.nearest_nodes()

    if Utils.key_in_node_list?(storage_nodes, Crypto.node_public_key(0)) do
      TransactionChain.get(address)
    else
      %TransactionList{transactions: chain} =
        storage_nodes
        |> P2P.broadcast_message(%GetTransactionChain{address: address})
        |> Enum.at(0)

      chain
    end
  end

  @doc """
  Retrieve the number of transaction in a transaction chain
  """
  @spec get_transaction_chain_length(binary()) :: non_neg_integer()
  def get_transaction_chain_length(address) do
    storage_nodes =
      address
      |> Replication.chain_storage_nodes(P2P.list_nodes(availability: :global))
      |> P2P.nearest_nodes()

    if Utils.key_in_node_list?(storage_nodes, Crypto.node_public_key(0)) do
      TransactionChain.size(address)
    else
      %TransactionChainLength{length: length} =
        storage_nodes
        |> P2P.broadcast_message(%GetTransactionChainLength{address: address})
        |> Enum.at(0)

      length
    end
  end
end
