defmodule Uniris.SelfRepair.Sync.BeaconSummaryHandler.TransactionHandler do
  @moduledoc false

  alias Uniris.BeaconChain.Slot.TransactionSummary

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetTransaction

  alias Uniris.Replication

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp

  alias Uniris.Utils

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
    node_list = [P2P.get_node_info() | P2P.authorized_nodes()] |> P2P.distinct_nodes()
    chain_storage_nodes = Replication.chain_storage_nodes_with_type(address, type, node_list)

    if Utils.key_in_node_list?(chain_storage_nodes, Crypto.node_public_key(0)) do
      true
    else
      Enum.any?(mvt_addresses, fn address ->
        io_storage_nodes = Replication.chain_storage_nodes(address, node_list)
        node_pool_address = Crypto.hash(Crypto.node_public_key())

        Utils.key_in_node_list?(io_storage_nodes, Crypto.node_public_key(0)) or
          address == node_pool_address
      end)
    end
  end

  @doc """
  Request the transaction for the closest storage nodes and replicate it locally.
  """
  @spec download_transaction(TransactionSummary.t(), patch :: binary()) ::
          :ok | {:error, :invalid_transaction}
  def download_transaction(%TransactionSummary{address: address, type: type}, node_patch)
      when is_binary(node_patch) do
    Logger.info("Synchronize missed transaction", transaction: "#{type}@#{Base.encode16(address)}")

    storage_nodes =
      address
      |> Replication.chain_storage_nodes_with_type(type)
      |> Enum.reject(&(&1.first_public_key == Crypto.node_public_key(0)))

    case P2P.reply_first(storage_nodes, %GetTransaction{address: address}) do
      {:ok, tx = %Transaction{validation_stamp: %ValidationStamp{ledger_operations: ops}}} ->
        node_list = [P2P.get_node_info() | P2P.authorized_nodes()] |> P2P.distinct_nodes()

        roles =
          [
            chain:
              Replication.chain_storage_node?(
                address,
                type,
                Crypto.node_public_key(),
                node_list
              ),
            IO: Replication.io_storage_node?(ops, Crypto.node_public_key(), node_list)
          ]
          |> Utils.get_keys_from_value_match(true)

        Replication.process_transaction(tx, roles, self_repair?: true)

      _ ->
        raise "Transaction #{Base.encode16(address)} not found from remote nodes during self repair"
    end
  end
end
