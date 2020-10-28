defmodule Uniris.BeaconChain do
  @moduledoc """
  Manage the beacon chain by providing functions to add to the subsets information and
  to retrieve the beacon storage nodes involved.
  """

  alias Uniris.Election

  alias Uniris.BeaconChain.Slot.TransactionInfo
  alias Uniris.BeaconChain.SlotTimer
  alias Uniris.BeaconChain.Subset

  alias Uniris.P2P

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  @doc """
  Initialize the beacon subsets (from 0 to 255 for a byte capacity)
  """
  def init_subsets do
    subsets = Enum.map(0..255, &:binary.encode_unsigned(&1))
    :persistent_term.put(:beacon_subsets, subsets)
  end

  @doc """
  List of all transaction subsets (255 subsets for a byte capacity)

  ## Examples

      BeaconChain.list_subsets()
      [ <<0>>, <<1>>,<<2>>, <<3>> ... <<253>>, <<254>>, <255>>]
  """
  @spec list_subsets() :: list(binary())
  def list_subsets do
    :persistent_term.get(:beacon_subsets)
  end

  @doc """
  Retrieve the beacon storage nodes from a last synchronization date

  For each subsets available, the computation will be done to find out the missing synchronization slots
  """
  @spec get_pools(DateTime.t()) :: list({subset :: binary(), nodes: list(Node.t())})
  def get_pools(last_sync_date = %DateTime{}) do
    slot_times = SlotTimer.previous_slots(last_sync_date)
    nodes_by_subset(list_subsets(), slot_times, [])
  end

  defp nodes_by_subset([subset | rest], slots_times, acc) do
    nodes =
      slots_times
      |> Stream.transform([], fn slot_time, acc ->
        nodes = get_pool(subset, slot_time)
        {nodes, acc}
      end)
      |> Stream.uniq_by(& &1.first_public_key)
      |> Enum.to_list()

    nodes_by_subset(rest, slots_times, [{subset, nodes} | acc])
  end

  defp nodes_by_subset([], _slots_times, acc), do: acc

  @doc """
  Retrieve the beacon storage nodes from a given subset and datetime
  """
  @spec get_pool(subset :: binary(), last_sync_date :: DateTime.t()) :: list(Node.t())
  def get_pool(subset, date = %DateTime{}) when is_binary(subset) do
    next_slot_date = SlotTimer.next_slot(date)

    storage_nodes =
      [authorized?: true, availability: :global]
      |> P2P.list_nodes()
      |> Enum.filter(&(DateTime.compare(&1.authorization_date, date) == :lt))

    Election.beacon_storage_nodes(
      subset,
      next_slot_date,
      storage_nodes
    )
  end

  @doc """
  Extract the beacon subset from an address

  ## Examples

      iex> BeaconChain.subset_from_address(<<0, 44, 242, 77, 186, 95, 176, 163,
      ...> 14, 38, 232, 59, 42, 197, 185, 226, 158, 51, 98, 147, 139, 152, 36,
      ...> 27, 22, 30, 92, 31, 167, 66, 94, 115, 4, >>)
      <<44>>
  """
  @spec subset_from_address(binary()) :: binary()
  def subset_from_address(address) do
    :binary.part(address, 1, 1)
  end

  @doc """
  Add a transaction to the beacon chain
  """
  @spec add_transaction(Transaction.t()) :: :ok
  def add_transaction(%Transaction{
        address: address,
        timestamp: timestamp,
        type: type,
        validation_stamp: %ValidationStamp{
          ledger_operations: operations
        }
      }) do
    movements_addresses = LedgerOperations.movement_addresses(operations)

    address
    |> subset_from_address()
    |> Subset.add_transaction_info(%TransactionInfo{
      address: address,
      timestamp: timestamp,
      movements_addresses: movements_addresses,
      type: type
    })
  end

  @doc """
  Give the next beacon chain slot using the `SlotTimer` interval
  """
  @spec next_slot(DateTime.t()) :: DateTime.t()
  defdelegate next_slot(date), to: SlotTimer
end
