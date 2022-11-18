defmodule Archethic.Replication.TransactionContext do
  @moduledoc false

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionInput

  require Logger

  @doc """
  Fetch transaction
  """
  @spec fetch_transaction(address :: Crypto.versioned_hash(), list(Node.t())) ::
          Transaction.t() | nil
  def fetch_transaction(address, node_list) when is_binary(address) do
    storage_nodes = Election.chain_storage_nodes(address, node_list)

    case TransactionChain.fetch_transaction_remotely(address, storage_nodes) do
      {:ok, tx} ->
        tx

      {:error, :transaction_not_exists} ->
        nil
    end
  end

  @doc """
  Stream transaction chain
  """
  @spec stream_transaction_chain(address :: Crypto.versioned_hash(), list(Node.t())) ::
          Enumerable.t() | list(Transaction.t())
  def stream_transaction_chain(address, node_list) when is_binary(address) do
    storage_nodes = Election.chain_storage_nodes(address, node_list)
    paging_address = TransactionChain.get_last_local_address(address)

    case storage_nodes do
      [] ->
        []

      _ ->
        if paging_address != address do
          TransactionChain.stream_remotely(address, storage_nodes, paging_address)
        else
          []
        end
    end
  end

  @doc """
  Fetch the transaction inputs for a transaction address at a given time
  """
  @spec fetch_transaction_inputs(address :: Crypto.versioned_hash(), DateTime.t(), list(Node.t())) ::
          list(TransactionInput.t())
  def fetch_transaction_inputs(address, timestamp = %DateTime{}, node_list)
      when is_binary(address) do
    storage_nodes = Election.chain_storage_nodes(address, node_list)

    address
    |> TransactionChain.stream_inputs_remotely(storage_nodes, timestamp)
    |> Enum.to_list()
  end
end
