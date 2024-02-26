defmodule Archethic.Replication.TransactionContext do
  @moduledoc false

  alias Archethic.BeaconChain
  alias Archethic.Crypto

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
  @spec fetch_transaction_unspent_outputs(transaction :: Transaction.t()) ::
          list(VersionedUnspentOutput.t())
  def fetch_transaction_unspent_outputs(tx) do
    authorized_nodes = P2P.authorized_and_available_nodes()
    previous_address = Transaction.previous_address(tx)
    previous_storage_nodes = Election.chain_storage_nodes(previous_address, authorized_nodes)

    {:ok, genesis_address} =
      TransactionChain.fetch_genesis_address(previous_address, previous_storage_nodes)

    previous_summary_time = BeaconChain.previous_summary_time(DateTime.utc_now())

    genesis_storage_nodes = genesis_address
    |> Election.chain_storage_nodes(authorized_nodes)
    |> Election.get_synchronized_nodes_before(previous_summary_time)

    Logger.debug(
      "Fetch inputs for #{Base.encode16(genesis_address)}",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    TransactionChain.fetch_unspent_outputs(genesis_address, genesis_storage_nodes)
    |> Enum.to_list()
    |> tap(fn inputs ->
      Logger.debug("Got #{inspect(inputs)} for #{Base.encode16(genesis_address)}",
        transaction_address: Base.encode16(tx.address),
        type: tx.type
      )
    end)
  end
end
