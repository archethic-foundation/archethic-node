defmodule UnirisBeacon do

  alias __MODULE__.Subset
  alias UnirisCrypto, as: Crypto
  alias UnirisElection, as: Election
  alias UnirisP2P, as: P2P

  @doc """
  List of all transaction subsets
  """
  @spec all_subsets() :: list(binary())
  def all_subsets() do
    [{_, subsets}] = :ets.lookup(:beacon_cache, :subsets)
    subsets
  end

  @doc """
  Retrieve the beacon storage nodes from a last synchronization date

  For each subsets availabile, the computation will be done to find out the missing synchronization slots
  """
  def get_pools(last_sync_date) do
    slot_interval = Application.get_env(:uniris_beacon, :slot_interval)
    sync_offset_time = DateTime.diff(DateTime.utc_now(), last_sync_date)
    sync_times = trunc(sync_offset_time / slot_interval)

    Enum.reduce(all_subsets(), %{}, fn subset, acc ->
      nodes =
        Enum.map(0..sync_times, fn i ->
          beacon_wrap_time = DateTime.add(last_sync_date, i * slot_interval) |> DateTime.to_unix()

          subset
          |> Crypto.derivate_beacon_chain_address(beacon_wrap_time)
          |> Election.storage_nodes()
          |> Enum.reject(&(&1.last_public_key == Crypto.node_public_key()))
          |> P2P.nearest_nodes()
        end)
        |> Enum.flat_map(& &1)
        |> Enum.uniq()

      Map.update(acc, subset, nodes, &Enum.uniq(&1 ++ nodes))
    end)
  end

  @doc """
  Add the transaction address and timestamp to a beacon subset
  """
  @spec add_transaction(binary, integer) :: :ok
  def add_transaction(address, timestamp)
      when is_binary(address) and is_integer(timestamp) do
    Subset.add_transaction(address, timestamp)
  end

  @doc """
  List the addresses before the last synchronized date for the given subset
  """
  @spec get_addresses(binary(), integer()) :: [binary]
  def get_addresses(subset, last_sync_date)
      when is_binary(subset) and is_integer(last_sync_date) do
    Subset.addresses(subset, last_sync_date)
  end

  @doc """
  Extract the beacon subset from an address

  ## Examples

     iex> UnirisBeacon.subset_from_address(<<0, 44, 242, 77, 186, 95, 176, 163,
     ...> 14, 38, 232, 59, 42, 197, 185, 226, 158, 51, 98, 147, 139, 152, 36,
     ...> 27, 22, 30, 92, 31, 167, 66, 94, 115, 4, >>)
     <<44>>
  """
  @spec subset_from_address(binary()) :: binary()
  def subset_from_address(address) do
    :binary.part(address, 1, 1)
  end

end
