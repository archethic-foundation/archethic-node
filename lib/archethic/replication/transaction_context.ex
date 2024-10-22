defmodule Archethic.Replication.TransactionContext do
  @moduledoc false

  alias Archethic.BeaconChain
  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.P2P
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  require Logger

  @doc """
  Fetch transaction
  """
  @spec fetch_transaction(address :: Crypto.versioned_hash(), opts :: Keyword.t()) ::
          Transaction.t() | nil
  def fetch_transaction(address, opts \\ []) when is_binary(address) do
    storage_nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

    case TransactionChain.fetch_transaction(address, storage_nodes, opts) do
      {:ok, tx} ->
        tx

      {:error, _} ->
        nil
    end
  end

  @doc """
  Fetch genesis address
  """
  @spec fetch_genesis_address(address :: Crypto.prepended_hash(), opts :: Keyword.t()) ::
          genesis_address :: Crypto.prepended_hash()
  def fetch_genesis_address(address, opts \\ []) do
    storage_nodes = Election.chain_storage_nodes(address, P2P.authorized_and_available_nodes())

    case TransactionChain.fetch_genesis_address(address, storage_nodes, opts) do
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
        |> ensure_all_tx_fetched(paging_address, genesis_address, limit_address)
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

  defp ensure_all_tx_fetched(transactions, paging_address, genesis_address, limit_address) do
    paging_address = if paging_address == nil, do: genesis_address, else: paging_address

    Stream.transform(
      transactions,
      # init accumulator
      fn -> paging_address end,
      # loop over transactions
      fn tx = %Transaction{address: address}, expected_previous_address ->
        if Transaction.previous_address(tx) != expected_previous_address do
          raise(
            "Replication failed to fetch previous chain after #{Base.encode16(expected_previous_address)}"
          )
        end

        {[tx], address}
      end,
      # after all tx processed
      fn last_address ->
        if last_address != limit_address do
          raise "Replication failed to fetch previous chain after #{Base.encode16(last_address)}"
        end
      end
    )
  end
end
