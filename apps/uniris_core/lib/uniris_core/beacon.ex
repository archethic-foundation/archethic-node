defmodule UnirisCore.Beacon do
  alias UnirisCore.BeaconSubset
  alias UnirisCore.BeaconSubsets
  alias UnirisCore.BeaconSlotTimer
  alias UnirisCore.BeaconSlot
  alias UnirisCore.BeaconSlot.TransactionInfo
  alias UnirisCore.BeaconSlot.NodeInfo
  alias UnirisCore.Crypto
  alias UnirisCore.Election
  alias UnirisCore.P2P

  @doc """
  List of all transaction subsets (255 subsets for a byte capacity)
  """
  @spec all_subsets() :: list(binary())
  def all_subsets() do
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
        DateTime.add(last_sync_date, i * slot_interval, :millisecond)
      end)

    Flow.from_enumerable(all_subsets())
    |> Flow.partition(stages: 256)
    |> Flow.reduce(fn -> %{} end, fn subset, acc ->
      nodes =
        slot_times
        |> Enum.map(&get_pool(subset, &1))
        |> Enum.flat_map(& &1)
        |> Enum.uniq()

      Map.update(acc, subset, nodes, &Enum.uniq(&1 ++ nodes))
    end)
    |> Enum.to_list()
  end

  @doc """
  Retrieve the beacon storage nodes from a given subset and datetime
  """
  @spec get_pool(subset :: binary(), date :: DateTime.t()) :: list(Node.t())
  def get_pool(subset, date = %DateTime{}) when is_binary(subset) do
    authorized_nodes =
      Enum.filter(P2P.list_nodes(), fn node ->
        DateTime.compare(node.enrollment_date, date) == :lt && node.ready? && node.authorized? &&
          node.availability == 1
      end)

    subset
    |> Crypto.derivate_beacon_chain_address(next_slot(date))
    |> Election.storage_nodes(authorized_nodes)
  end

  defp next_slot(date) do
    if DateTime.diff(date, BeaconSlotTimer.last_slot_time()) > 0 do
      DateTime.add(date, BeaconSlotTimer.slot_interval())
    else
      BeaconSlotTimer.last_slot_time()
    end
  end

  @doc """
  Get the last informations regarding a beacon subset slot before the last synchronized date for the given subset.
  """
  @spec previous_slots(subset :: <<_::8>>, DateTime.t()) :: BeaconSlot.t()
  def previous_slots(subset, last_sync_date = %DateTime{}) when is_binary(subset) do
    BeaconSubset.previous_slots(subset, last_sync_date)
  end

  @doc """
  Extract the beacon subset from an address

  ## Examples

    iex> UnirisCore.Beacon.subset_from_address(<<0, 44, 242, 77, 186, 95, 176, 163,
    ...> 14, 38, 232, 59, 42, 197, 185, 226, 158, 51, 98, 147, 139, 152, 36,
    ...> 27, 22, 30, 92, 31, 167, 66, 94, 115, 4, >>)
    <<44>>
  """
  @spec subset_from_address(binary()) :: binary()
  def subset_from_address(address) do
    :binary.part(address, 1, 1)
  end

  @doc """
  Add the transaction information to the current slot for the given subset
  """
  @spec add_transaction_info(subset :: binary(), TransactionInfo.t()) :: :ok
  def add_transaction_info(subset, info = %TransactionInfo{}) when is_binary(subset) do
    BeaconSubset.add_transaction_info(subset, info)
  end

  @doc """
  Add node informations to the current block of the given subset
  """
  @spec add_node_info(subset :: binary(), NodeInfo.t()) :: :ok
  def add_node_info(subset, info = %NodeInfo{}) do
    BeaconSubset.add_node_info(subset, info)
  end
end
