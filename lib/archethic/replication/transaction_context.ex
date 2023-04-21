defmodule Archethic.Replication.TransactionContext do
  @moduledoc false

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionInput

  alias Archethic.P2P

  require Logger

  @doc """
  Fetch transaction
  """
  @spec fetch_transaction(address :: Crypto.versioned_hash()) ::
          Transaction.t() | nil
  def fetch_transaction(address) when is_binary(address) do
    storage_nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

    case TransactionChain.fetch_transaction_remotely(address, storage_nodes) do
      {:ok, tx} ->
        tx

      {:error, _} ->
        nil
    end
  end

  @doc """
  Stream transaction chain
  """
  @spec stream_transaction_chain(address :: Crypto.versioned_hash(), list(Node.t())) ::
          Enumerable.t() | list(Transaction.t())
  def stream_transaction_chain(address, node_list) when is_binary(address) do
    with storage_nodes <- Election.chain_storage_nodes(address, node_list),
         {:ok, genesis_address} <-
           TransactionChain.fetch_genesis_address_remotely(address, storage_nodes),
         true <- address != genesis_address,
         paging_address <- TransactionChain.get_last_stored_address(genesis_address),
         true <- paging_address != address do
      TransactionChain.stream_remotely(address, storage_nodes, paging_address)
      |> Stream.take_while(&(Transaction.previous_address(&1) != address))
    else
      _ -> []
    end
  end

  @doc """
  Fetch the transaction inputs for a transaction address at a given time
  """
  @spec fetch_transaction_inputs(address :: Crypto.versioned_hash(), DateTime.t()) ::
          list(TransactionInput.t())
  def fetch_transaction_inputs(address, timestamp = %DateTime{})
      when is_binary(address) do
    storage_nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

    address
    |> TransactionChain.stream_inputs_remotely(storage_nodes, timestamp)
    |> Enum.to_list()
  end
end
