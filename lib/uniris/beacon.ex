defmodule Uniris.Beacon do
  @moduledoc """
  Manage the beacon chain by providing functions to add to the subsets informations and
  to retrieve the beacon storage nodes involved.
  """

  alias Uniris.Crypto
  alias Uniris.Election

  alias Uniris.BeaconSlot
  alias Uniris.BeaconSlot.NodeInfo
  alias Uniris.BeaconSlot.TransactionInfo
  alias Uniris.BeaconSlotTimer

  alias Uniris.BeaconSubset
  alias Uniris.BeaconSubsets

  alias Uniris.P2P

  alias Uniris.Transaction
  alias Uniris.Transaction.ValidationStamp
  alias Uniris.Transaction.ValidationStamp.LedgerOperations

  alias Uniris.Utils

  @doc """
  List of all transaction subsets (255 subsets for a byte capacity)
  """
  @spec all_subsets() :: list(binary())
  def all_subsets do
    BeaconSubsets.all()
  end

  @doc """
  Retrieve the beacon storage nodes from a last synchronization date

  For each subsets availabile, the computation will be done to find out the missing synchronization slots
  """
  @spec get_pools(DateTime.t()) :: list({subset :: binary(), nodes: list(Node.t())})
  def get_pools(last_sync_date = %DateTime{}) do
    slot_interval = BeaconSlotTimer.slot_interval()
    sync_offset_time = DateTime.diff(DateTime.utc_now(), last_sync_date, :millisecond)
    sync_times = trunc(sync_offset_time / slot_interval)

    slot_times =
      Enum.map(0..sync_times, fn i ->
        last_sync_date
        |> DateTime.add(i * slot_interval, :millisecond)
        |> Utils.truncate_datetime()
      end)

    Flow.from_enumerable(BeaconSubsets.all())
    |> Flow.partition(stages: 256)
    |> Flow.reduce(fn -> %{} end, fn subset, acc ->
      slot_times
      |> Enum.map(fn slot_time -> {slot_time, get_pool(subset, slot_time)} end)
      |> Enum.reject(fn {_, nodes} -> nodes == [] end)
      |> case do
        [] ->
          acc

        nodes ->
          Map.update(acc, subset, nodes, &Enum.uniq(&1 ++ nodes))
      end
    end)
    |> Enum.to_list()
  end

  @doc """
  Retrieve the beacon storage nodes from a given subset and datetime
  """
  @spec get_pool(subset :: binary(), last_sync_date :: DateTime.t()) :: list(Node.t())
  def get_pool(subset, date = %DateTime{}) when is_binary(subset) do
    # Need to select the beacon authorized nodes at the last sync date
    authorized_nodes =
      Enum.filter(
        P2P.list_nodes(),
        &(&1.ready? && &1.available? && &1.authorized? &&
            DateTime.compare(&1.authorization_date, date) == :lt)
      )

    subset
    |> Crypto.derivate_beacon_chain_address(next_slot(date))
    |> Election.storage_nodes(authorized_nodes)
  end

  defp next_slot(date) do
    last_slot_time = BeaconSlotTimer.last_slot_time()

    if DateTime.diff(date, last_slot_time) > 0 do
      DateTime.add(date, BeaconSlotTimer.slot_interval())
    else
      last_slot_time
    end
    |> Utils.truncate_datetime()
  end

  @doc """
  Get the last informations regarding a beacon subset slot before the last synchronized dates for the given subset.
  """
  @spec previous_slots(subset :: <<_::8>>, dates :: list(DateTime.t())) :: list(BeaconSlot.t())
  def previous_slots(subset, dates) when is_binary(subset) and is_list(dates) do
    BeaconSubset.previous_slots(subset, dates)
  end

  @doc """
  Extract the beacon subset from an address

  ## Examples

    iex> Uniris.Beacon.subset_from_address(<<0, 44, 242, 77, 186, 95, 176, 163,
    ...> 14, 38, 232, 59, 42, 197, 185, 226, 158, 51, 98, 147, 139, 152, 36,
    ...> 27, 22, 30, 92, 31, 167, 66, 94, 115, 4, >>)
    <<44>>
  """
  @spec subset_from_address(binary()) :: binary()
  def subset_from_address(address) do
    :binary.part(address, 1, 1)
  end

  @doc """
  Add node informations to the current block of the given subset
  """
  @spec add_node_info(subset :: binary(), NodeInfo.t()) :: :ok
  def add_node_info(subset, info = %NodeInfo{}) do
    BeaconSubset.add_node_info(subset, info)
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
          ledger_operations: %LedgerOperations{
            node_movements: node_movements,
            transaction_movements: transaction_movements
          }
        }
      }) do
    movements_addresses =
      Enum.map(node_movements, &Crypto.hash(&1.to)) ++ Enum.map(transaction_movements, & &1.to)

    address
    |> subset_from_address()
    |> BeaconSubset.add_transaction_info(%TransactionInfo{
      address: address,
      timestamp: timestamp,
      movements_addresses: movements_addresses,
      type: type
    })
  end
end
