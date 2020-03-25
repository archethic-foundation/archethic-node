defmodule UnirisSync do
  @moduledoc """
  Represents the synchronisation of the Uniris network by starting up the bootstrap process when a node startup,
  Self-Repair mechanism and replication, Beacon chain subsets register
  and system transaction loading based on transaction type behaviour
  """

  alias UnirisChain.Transaction
  alias __MODULE__.Beacon.Subset, as: BeaconSubset
  alias __MODULE__.TransactionLoader

  def notify_new_transaction(address) do
    Registry.dispatch(UnirisSync.PubSub, "new_transaction", fn entries ->
      for {pid, _} <- entries, do: send(pid, {:new_transaction, address})
    end)
  end

  def register_to_new_transaction() do
    Registry.register(UnirisSync.PubSub, "new_transaction", [])
  end

  @doc """
  Load the new stored transaction in the system with specific behaviour regarding its type:
  - Node transaction: add and start supervised connection to the new node
  - Node shared secrets: authorize nodes and renew shared key
  etc..
  """
  @spec load_transaction(UnirisChain.Transaction.t()) :: :ok
  def load_transaction(tx = %Transaction{}) do
    TransactionLoader.new_transaction(tx)
  end

  @doc """
  Add the transaction address and timestamp to a beacon subset
  """
  @spec add_transaction_to_beacon(binary, integer) :: :ok
  def add_transaction_to_beacon(address, timestamp)
      when is_binary(address) and is_integer(timestamp) do
    BeaconSubset.add_transaction(address, timestamp)
  end

  @doc """
  List the addresses before the last synchronized date for the given subset
  """
  @spec get_beacon_addresses(binary(), integer()) :: [binary]
  def get_beacon_addresses(subset, last_sync_date) when is_binary(subset) and is_integer(last_sync_date) do
    BeaconSubset.addresses(subset, last_sync_date)
  end

  @doc """
  Extract the beacon subset from an address

  ## Examples

     iex> UnirisSync.beacon_subset_from_address(<<0, 44, 242, 77, 186, 95, 176, 163,
     ...> 14, 38, 232, 59, 42, 197, 185, 226, 158, 51, 98, 147, 139, 152, 36,
     ...> 27, 22, 30, 92, 31, 167, 66, 94, 115, 4, >>)
     <<44>>
  """
  @spec beacon_subset_from_address(binary()) :: binary()
  def beacon_subset_from_address(address) do
    BeaconSubset.from_address(address)
  end
end
