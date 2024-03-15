defmodule Archethic.Replication.TransactionContext do
  @moduledoc false

  alias Archethic.Crypto

  alias Archethic.BeaconChain

  alias Archethic.Election

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.P2P

  require Logger

  @doc """
  Fetch transaction
  """
  @spec fetch_transaction(address :: Crypto.versioned_hash()) ::
          Transaction.t() | nil
  def fetch_transaction(address) when is_binary(address) do
    storage_nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

    case TransactionChain.fetch_transaction(address, storage_nodes) do
      {:ok, tx} ->
        tx

      {:error, _} ->
        nil
    end
  end

  @doc """
  Fetch genesis address
  """
  @spec fetch_genesis_address(address :: Crypto.prepended_hash()) ::
          genesis_address :: Crypto.prepended_hash()
  def fetch_genesis_address(address) do
    storage_nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

    case TransactionChain.fetch_genesis_address(address, storage_nodes) do
      {:ok, genesis_address} -> genesis_address
      {:error, _} -> address
    end
  end

  @doc """
  Stream transaction chain
  """
  @spec stream_transaction_chain(
          genesis_address :: Crypto.prepended_hash(),
          limit_address :: Crypto.prepended_hash(),
          nodes :: list(Node.t())
        ) :: Enumerable.t() | list(Transaction.t())
  def stream_transaction_chain(genesis_address, limit_address, node_list) do
    case TransactionChain.get_last_stored_address(genesis_address) do
      ^limit_address ->
        []

      paging_address ->
        storage_nodes = Election.chain_storage_nodes(limit_address, node_list)

        genesis_address
        |> TransactionChain.fetch(storage_nodes, paging_state: paging_address)
        |> Stream.take_while(&(Transaction.previous_address(&1) != limit_address))
    end
  end

  @doc """
  Fetch the transaction unspent outputs for a transaction address at a given time
  """
  @spec fetch_transaction_unspent_outputs(genesis_address :: Crypto.prepended_hash()) ::
          list(VersionedUnspentOutput.t())
  def fetch_transaction_unspent_outputs(genesis_address) do
    previous_summary_time = BeaconChain.previous_summary_time(DateTime.utc_now())

    genesis_nodes =
      genesis_address
      |> Election.chain_storage_nodes(P2P.authorized_and_available_nodes())
      |> Election.get_synchronized_nodes_before(previous_summary_time)

    TransactionChain.fetch_unspent_outputs(genesis_address, genesis_nodes) |> Enum.to_list()
  end
end
