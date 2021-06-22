defmodule ArchEthic.SelfRepair.Sync.BeaconSummaryHandler.TransactionHandler do
  @moduledoc false

  alias ArchEthic.BeaconChain.Slot.TransactionSummary

  alias ArchEthic.Crypto

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.GetTransaction
  alias ArchEthic.P2P.Message.NotFound

  alias ArchEthic.Replication

  alias ArchEthic.TransactionChain.Transaction

  alias ArchEthic.Utils

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

    if Utils.key_in_node_list?(chain_storage_nodes, Crypto.first_node_public_key()) do
      true
    else
      Enum.any?(mvt_addresses, fn address ->
        io_storage_nodes = Replication.chain_storage_nodes(address, node_list)
        node_pool_address = Crypto.hash(Crypto.last_node_public_key())

        Utils.key_in_node_list?(io_storage_nodes, Crypto.first_node_public_key()) or
          address == node_pool_address
      end)
    end
  end

  @doc """
  Request the transaction for the closest storage nodes and replicate it locally.
  """
  @spec download_transaction(TransactionSummary.t(), patch :: binary()) ::
          :ok | {:error, :invalid_transaction}
  def download_transaction(
        %TransactionSummary{address: address, type: type, timestamp: timestamp},
        node_patch
      )
      when is_binary(node_patch) do
    Logger.info("Synchronize missed transaction", transaction: "#{type}@#{Base.encode16(address)}")

    storage_nodes =
      case P2P.authorized_nodes(timestamp) do
        [] ->
          Replication.chain_storage_nodes_with_type(address, type)

        nodes ->
          Replication.chain_storage_nodes_with_type(address, type, nodes)
      end

    response =
      storage_nodes
      |> Enum.reject(&(&1.first_public_key == Crypto.first_node_public_key()))
      |> P2P.reply_first(%GetTransaction{address: address})

    case response do
      {:ok, tx = %Transaction{}} ->
        node_list = [P2P.get_node_info() | P2P.authorized_nodes()] |> P2P.distinct_nodes()

        roles =
          [
            chain:
              Replication.chain_storage_node?(
                address,
                type,
                Crypto.last_node_public_key(),
                node_list
              ),
            IO: Replication.io_storage_node?(tx, Crypto.last_node_public_key(), node_list)
          ]
          |> Utils.get_keys_from_value_match(true)

        Replication.process_transaction(tx, roles, self_repair?: true)

      {:ok, %NotFound{}} ->
        Logger.error("Transaction not found from remote nodes during self repair",
          transaction: "#{type}@#{Base.encode16(address)}"
        )

      {:error, :network_issue} ->
        Logger.error("Network issue during during self repair",
          transaction: "#{type}@#{Base.encode16(address)}"
        )
    end
  end
end
