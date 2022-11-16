defmodule Archethic.SelfRepair.Sync.TransactionHandler do
  @moduledoc false

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.Replication

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionSummary

  alias Archethic.Utils

  require Logger

  @doc """
  Determine if the transaction should be downloaded by the local node.

  Verify firstly the chain storage nodes election.
  If not successful, perform storage nodes election based on the transaction movements.
  """
  @spec download_transaction?(TransactionSummary.t()) :: boolean()
  def download_transaction?(%TransactionSummary{
        address: address,
        type: type,
        movements_addresses: mvt_addresses
      }) do
    node_list =
      [P2P.get_node_info() | P2P.authorized_and_available_nodes()] |> P2P.distinct_nodes()

    chain_storage_nodes = Election.chain_storage_nodes_with_type(address, type, node_list)

    if Utils.key_in_node_list?(chain_storage_nodes, Crypto.first_node_public_key()) do
      true
    else
      Enum.any?(mvt_addresses, fn address ->
        io_storage_nodes = Election.chain_storage_nodes(address, node_list)
        node_pool_address = Crypto.hash(Crypto.last_node_public_key())

        Utils.key_in_node_list?(io_storage_nodes, Crypto.first_node_public_key()) or
          address == node_pool_address
      end)
    end
  end

  @doc """
  Request the transaction for the closest storage nodes and replicate it locally.
  """
  @spec download_transaction(TransactionSummary.t(), patch :: binary(), list(Node.t())) ::
          Transaction.t()
  def download_transaction(
        %TransactionSummary{address: address, type: type, timestamp: _timestamp},
        node_patch,
        download_nodes
      )
      when is_binary(node_patch) do
    Logger.info("Synchronize missed transaction",
      transaction_address: Base.encode16(address),
      transaction_type: type
    )

    storage_nodes =
      address
      |> Election.chain_storage_nodes_with_type(type, download_nodes)
      |> Enum.reject(&(&1.first_public_key == Crypto.first_node_public_key()))
      |> P2P.nearest_nodes()
      |> Enum.filter(&Node.locally_available?/1)

    case TransactionChain.fetch_transaction_remotely(address, storage_nodes) do
      {:ok, tx = %Transaction{}} ->
        tx

      {:error, :transaction_not_exists} ->
        Logger.error("Cannot fetch the transaction to sync",
          transaction_address: Base.encode16(address),
          transaction_type: type
        )

        raise "Transaction doesn't exist"

      {:error, :network_issue} ->
        Logger.error("Cannot fetch the transaction to sync",
          transaction_address: Base.encode16(address),
          transaction_type: type
        )

        raise "Network issue during during self repair"
    end
  end

  @spec process_transaction(Transaction.t(), list(Node.t())) ::
          :ok | {:error, :invalid_transaction}
  def process_transaction(
        tx = %Transaction{
          address: address,
          type: type
        },
        download_nodes
      ) do
    node_list = [P2P.get_node_info() | download_nodes] |> P2P.distinct_nodes()

    cond do
      Election.chain_storage_node?(address, type, Crypto.first_node_public_key(), node_list) ->
        Replication.validate_and_store_transaction_chain(tx, true, download_nodes)

      Election.io_storage_node?(tx, Crypto.first_node_public_key(), node_list) ->
        Replication.validate_and_store_transaction(tx, true)

      true ->
        :ok
    end
  end
end
