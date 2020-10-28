defmodule Uniris.SelfRepair.Sync.SlotConsumer do
  @moduledoc false

  alias Uniris.BeaconChain.Slot, as: BeaconSlot

  alias Uniris.P2P

  alias __MODULE__.TransactionHandler

  alias Uniris.TransactionChain

  require Logger

  @doc """
  Process beacon slots to synchronize the transactions involving.

  Each transactions from the beacon slots will be analyzed to determine
  if the node is a storage node for this transaction. If so, it will download the
  transaction from the closest storage nodes and replicate it locally.

  The P2P view will also be updated if some node information are inside the beacon slots
  """
  @spec handle_missing_slots(Enumerable.t() | list(BeaconSlot.t()), binary()) :: :ok
  def handle_missing_slots(slots, node_patch) when is_binary(node_patch) do
    %BeaconSlot{transactions: transactions, nodes: nodes} = reduce_slots(slots)

    :ok = synchronize_transactions(transactions, node_patch)
    :ok = update_nodes_info(nodes)

    :ok
  end

  defp reduce_slots(slots) do
    Enum.reduce(slots, %BeaconSlot{}, fn %BeaconSlot{transactions: transactions, nodes: nodes},
                                         acc ->
      acc = Enum.reduce(nodes, acc, &BeaconSlot.add_node_info(&2, &1))
      acc = Enum.reduce(transactions, acc, &BeaconSlot.add_transaction_info(&2, &1))
      acc
    end)
  end

  defp synchronize_transactions(transactions_info, node_patch) do
    transactions_info
    |> Stream.reject(&TransactionChain.transaction_exists?(&1.address))
    |> Stream.filter(&TransactionHandler.download_transaction?/1)
    |> TransactionHandler.sort_transactions_information()
    |> Stream.each(&TransactionHandler.download_transaction(&1, node_patch))
    |> Stream.run()
  end

  defp update_nodes_info(nodes_info) do
    nodes_info
    |> Enum.filter(& &1.ready?)
    |> Enum.each(&P2P.set_node_globally_available(&1.public_key))
  end
end
