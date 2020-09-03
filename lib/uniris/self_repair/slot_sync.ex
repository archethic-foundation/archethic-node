defmodule Uniris.SelfRepair.SlotSync do
  @moduledoc false

  alias Uniris.BeaconSlot
  alias Uniris.BeaconSlot.NodeInfo
  alias Uniris.BeaconSlot.TransactionInfo
  alias Uniris.Crypto

  alias Uniris.Election

  alias Uniris.Mining.Replication

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetTransaction

  alias Uniris.Storage
  alias Uniris.Storage.Memory.NetworkLedger

  alias Uniris.Transaction

  require Logger

  def handle_missing_slots(slots, node_patch) do
    %BeaconSlot{transactions: transactions, nodes: nodes} = reduce_slots(slots)
    synchronize_transactions(transactions, node_patch)
    update_node_infos(nodes)
  end

  defp reduce_slots(slots) do
    Enum.reduce(slots, %BeaconSlot{}, fn %BeaconSlot{transactions: transactions, nodes: nodes},
                                         acc ->
      acc = Enum.reduce(nodes, acc, &BeaconSlot.add_node_info(&2, &1))
      Enum.reduce(transactions, acc, &BeaconSlot.add_transaction_info(&2, &1))
    end)
  end

  defp synchronize_transactions(transaction_infos, node_patch) do
    transaction_infos =
      transaction_infos
      |> Enum.reject(&transaction_exists?(&1.address))
      # Need to download the latest transactions and the the newest
      # to ensure transaction chain integrity verification
      |> Enum.sort_by(& &1.timestamp, :asc)
      |> Enum.sort_by(& &1.type, fn type, _ -> Transaction.network_type?(type) end)
      |> Enum.sort_by(& &1.type, fn type_a, type_b ->
        # TODO: same with other network type transactions
        cond do
          type_a == :node and type_b == :node_shared_secrets ->
            true

          type_a == :node_shared_secrets and type_b == :node ->
            false

          true ->
            true
        end
      end)

    Enum.each(transaction_infos, &download_transaction(&1, node_patch))
  end

  defp transaction_storage_nodes(%TransactionInfo{address: address, type: type}) do
    if Transaction.network_type?(type) do
      NetworkLedger.list_nodes()
    else
      Election.storage_nodes(address, NetworkLedger.list_nodes())
    end
  end

  defp download_transaction(
         tx_info = %TransactionInfo{address: address},
         node_patch
       ) do
    if !transaction_exists?(address) do
      process_missed_transaction(tx_info, node_patch)
    end
  end

  defp process_missed_transaction(
         tx_info = %TransactionInfo{
           address: address,
           type: type,
           movements_addresses: movements_addresses
         },
         node_patch
       ) do
    chain_storage_nodes = transaction_storage_nodes(tx_info)

    # Download the transaction if member of chain storage pool
    if Crypto.node_public_key(0) in Enum.map(chain_storage_nodes, & &1.first_public_key) do
      Logger.info("Download transaction #{type}@#{Base.encode16(address)}")
      do_download(address, chain_storage_nodes, node_patch)
    else
      # Download the transaction if member of IO storage pool (transaction movements, node movements)
      Enum.each(movements_addresses, &process_movement_address(&1, address, node_patch))
    end
  end

  defp process_movement_address(mvt_address, tx_address, node_patch) do
    io_storage_nodes = Election.storage_nodes(mvt_address, NetworkLedger.list_nodes())

    if Crypto.node_public_key(0) in Enum.map(io_storage_nodes, & &1.first_public_key) do
      Logger.info("Download transaction movement #{Base.encode16(tx_address)}")
      do_download(tx_address, io_storage_nodes, node_patch)
    end
  end

  defp do_download(address, storage_nodes, node_patch) do
    downloading_nodes =
      storage_nodes
      |> Stream.filter(& &1.ready?)
      |> Stream.reject(&(&1.first_public_key == Crypto.node_public_key(0)))
      |> Enum.to_list()
      |> P2P.nearest_nodes(node_patch)

    tx =
      %Transaction{previous_public_key: previous_public_key} =
      request_nodes(downloading_nodes, %GetTransaction{address: address})

    previous_chain =
      Storage.get_transaction_chain(Crypto.hash(previous_public_key)) |> Enum.to_list()

    next_chain = [tx | previous_chain]

    Logger.debug(
      "New transaction chain to store: #{
        inspect(Enum.map(next_chain, &Base.encode16(&1.address)))
      }"
    )

    with true <- Replication.valid_transaction?(tx),
         true <- Replication.valid_chain?(next_chain) do
      Storage.write_transaction_chain(next_chain)
    else
      _ ->
        Logger.error("Invalid transaction chain #{Base.encode16(tx.address)}")
    end
  end

  defp update_node_infos(node_infos) do
    Enum.each(node_infos, fn %NodeInfo{
                               public_key: public_key,
                               ready?: ready?,
                               timestamp: timestamp
                             } ->
      if ready? do
        NetworkLedger.set_node_ready(public_key, timestamp)
      end
    end)
  end

  defp request_nodes([node | rest], message) do
    case P2P.send_message(node, message) do
      tx = %Transaction{} ->
        tx

      _ ->
        request_nodes(rest, message)
    end
  end

  defp request_nodes([], _), do: {:error, :network_issue}

  defp transaction_exists?(address) do
    case Storage.get_transaction(address) do
      {:ok, _} ->
        true

      _ ->
        false
    end
  end
end
