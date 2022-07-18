defmodule Archethic.Replication.TransactionContext do
  @moduledoc false

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionInput

  require Logger

  @doc """
  Fetch transaction
  """
  @spec fetch_transaction(address :: Crypto.versioned_hash()) :: Transaction.t() | nil
  def fetch_transaction(address) when is_binary(address) do
    nodes = replication_nodes(address)

    case TransactionChain.fetch_transaction_remotely(address, nodes) do
      {:ok, tx} ->
        tx

      {:error, :transaction_not_exists} ->
        nil
    end
  end

  @doc """
  Stream transaction chain
  """
  @spec stream_transaction_chain(address :: Crypto.versioned_hash()) ::
          Enumerable.t() | list(Transaction.t())
  def stream_transaction_chain(address) when is_binary(address) do
    case replication_nodes(address) do
      [] ->
        []

      nodes ->
        case TransactionChain.get_from_local(address) do
          {false, nil} -> TransactionChain.stream_remotely(address, nodes)
          {true, last_address} -> TransactionChain.stream_remotely(address, nodes, last_address)
        end
    end
  end

  @doc """
  Fetch the transaction inputs for a transaction address at a given time
  """
  @spec fetch_transaction_inputs(address :: Crypto.versioned_hash(), DateTime.t()) ::
          list(TransactionInput.t())
  def fetch_transaction_inputs(address, timestamp = %DateTime{}) when is_binary(address) do
    nodes = replication_nodes(address)

    {:ok, inputs} = TransactionChain.fetch_inputs_remotely(address, nodes, timestamp)
    inputs
  end

  defp replication_nodes(address) do
    address
    # returns the storage nodes for the transaction chain based on the transaction address
    # from a list of available node
    |> Election.chain_storage_nodes(P2P.available_nodes())
    #  Returns the nearest storages nodes from the local node as per the patch
    #  when the input is a list of nodes
    |> P2P.nearest_nodes()
    # Determine if the node is locally available based on its availability history.
    # If the last exchange with node was succeed the node is considered as available
    |> Enum.filter(&Node.locally_available?/1)
    # Reorder a list of nodes to ensure the current node is only called at the end
    |> P2P.unprioritize_node(Crypto.first_node_public_key())
  end
end
