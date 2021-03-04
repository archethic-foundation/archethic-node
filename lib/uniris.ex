defmodule Uniris do
  @moduledoc """
  Provides high level functions serving the API and the Explorer
  """

  alias __MODULE__.Account
  alias __MODULE__.Crypto

  alias __MODULE__.Mining

  alias __MODULE__.P2P

  alias __MODULE__.P2P.Message
  alias __MODULE__.P2P.Message.Balance
  alias __MODULE__.P2P.Message.GetBalance
  alias __MODULE__.P2P.Message.GetLastTransaction
  alias __MODULE__.P2P.Message.GetTransaction
  alias __MODULE__.P2P.Message.GetTransactionChain
  alias __MODULE__.P2P.Message.GetTransactionChainLength
  alias __MODULE__.P2P.Message.GetTransactionInputs
  alias __MODULE__.P2P.Message.StartMining
  alias __MODULE__.P2P.Message.TransactionChainLength
  alias __MODULE__.P2P.Message.TransactionInputList
  alias __MODULE__.P2P.Message.TransactionList

  alias __MODULE__.Replication

  alias __MODULE__.TransactionChain.Transaction
  alias __MODULE__.TransactionChain.TransactionInput

  alias __MODULE__.Utils

  @doc """
  Query the search of the transaction to the dedicated storage pool
  """
  @spec search_transaction(address :: binary()) ::
          {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  def search_transaction(address) when is_binary(address) do
    storage_nodes =
      Replication.chain_storage_nodes(address, P2P.list_nodes(availability: :global))

    message = %GetTransaction{address: address}

    if Utils.key_in_node_list?(storage_nodes, Crypto.node_public_key(0)) do
      handle_transaction_result({:ok, Message.process(message)})
    else
      storage_nodes
      |> P2P.reply_first(message)
      |> handle_transaction_result()
    end
  end

  @doc """
  Send a new transaction in the network to be mined. The current node will act as welcome node
  """
  @spec send_new_transaction(Transaction.t()) :: :ok | {:error, :invalid_transaction}
  def send_new_transaction(tx = %Transaction{}) do
    validation_nodes = Mining.transaction_validation_nodes(tx)
    do_send_transaction(tx, validation_nodes)
  end

  defp do_send_transaction(tx, validation_nodes) do
    message = %StartMining{
      transaction: tx,
      welcome_node_public_key: Crypto.node_public_key(),
      validation_node_public_keys: Enum.map(validation_nodes, & &1.last_public_key)
    }

    P2P.broadcast_message(validation_nodes, message)
  end

  @spec get_last_transaction(address :: binary()) ::
          {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  def get_last_transaction(address) do
    message = %GetLastTransaction{address: address}

    case handle_transaction_result(Message.process(message)) do
      {:ok, tx} ->
        {:ok, tx}

      {:error, :transaction_not_exists} ->
        address
        |> Replication.chain_storage_nodes(P2P.list_nodes(availability: :global))
        |> P2P.reply_first(message)
        |> handle_transaction_result()
    end
  end

  defp handle_transaction_result(tx = %Transaction{}), do: {:ok, tx}
  defp handle_transaction_result({:ok, tx = %Transaction{}}), do: {:ok, tx}
  defp handle_transaction_result(_), do: {:error, :transaction_not_exists}

  @doc """
  Retrieve the balance from an address.

  If the current node is a storage of this address, it will perform a fast lookup
  Otherwise it will request the closest storage node about it
  """
  @spec get_balance(binary) :: Account.balance()
  def get_balance(address) when is_binary(address) do
    storage_nodes =
      Replication.chain_storage_nodes(address, P2P.list_nodes(availability: :global))

    message = %GetBalance{address: address}

    if Utils.key_in_node_list?(storage_nodes, Crypto.node_public_key(0)) do
      handle_balance_result({:ok, Message.process(message)})
    else
      storage_nodes
      |> P2P.reply_first(message)
      |> handle_balance_result()
    end
  end

  defp handle_balance_result({:ok, %Balance{uco: uco_balance, nft: nft_balances}}) do
    %{uco: uco_balance, nft: nft_balances}
  end

  defp handle_balance_result(_), do: %{uco: 0.0, nft: %{}}

  @doc """
  Request to fetch the inputs for a transaction address
  """
  @spec get_transaction_inputs(binary()) :: list(TransactionInput.t())
  def get_transaction_inputs(address) when is_binary(address) do
    storage_nodes =
      Replication.chain_storage_nodes(address, P2P.list_nodes(availability: :global))

    message = %GetTransactionInputs{address: address}

    if Utils.key_in_node_list?(storage_nodes, Crypto.node_public_key(0)) do
      handle_inputs_result({:ok, Message.process(message)})
    else
      storage_nodes
      |> P2P.reply_first(message)
      |> handle_inputs_result()
    end
  end

  defp handle_inputs_result({:ok, %TransactionInputList{inputs: inputs}}), do: inputs
  defp handle_inputs_result(_), do: []

  @doc """
  Retrieve a transaction chain based on an address
  """
  @spec get_transaction_chain(binary()) :: list(Transaction.t())
  def get_transaction_chain(address) when is_binary(address) do
    storage_nodes =
      Replication.chain_storage_nodes(address, P2P.list_nodes(availability: :global))

    message = %GetTransactionChain{address: address}

    if Utils.key_in_node_list?(storage_nodes, Crypto.node_public_key(0)) do
      handle_chain_result({:ok, Message.process(message)})
    else
      storage_nodes
      |> P2P.reply_first(message)
      |> handle_chain_result()
    end
  end

  defp handle_chain_result({:ok, %TransactionList{transactions: chain}}), do: chain
  defp handle_chain_result(_), do: []

  @doc """
  Retrieve the number of transaction in a transaction chain
  """
  @spec get_transaction_chain_length(binary()) :: non_neg_integer()
  def get_transaction_chain_length(address) when is_binary(address) do
    storage_nodes =
      Replication.chain_storage_nodes(address, P2P.list_nodes(availability: :global))

    message = %GetTransactionChainLength{address: address}

    if Utils.key_in_node_list?(storage_nodes, Crypto.node_public_key(0)) do
      handle_chain_length_result({:ok, Message.process(message)})
    else
      storage_nodes
      |> P2P.reply_first(message)
      |> handle_chain_length_result()
    end
  end

  defp handle_chain_length_result({:ok, %TransactionChainLength{length: length}}), do: length
  defp handle_chain_length_result(_), do: 0
end
