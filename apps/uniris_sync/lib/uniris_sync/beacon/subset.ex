defmodule UnirisSync.Beacon.Subset do
  @moduledoc false

  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.Data
  alias UnirisSync.BeaconSubsetRegistry

  use GenServer

  require Logger

  def start_link(opts) do
    subset = Keyword.get(opts, :subset)
    slot_interval = Keyword.get(opts, :slot_interval)
    startup_date = Keyword.get(opts, :startup_date)
    GenServer.start_link(__MODULE__, [subset, slot_interval, startup_date], name: via_tuple(subset))
  end

  def init([subset, slot_interval, startup_date]) do
    schedule_slot(slot_interval)

    {:ok,
     %{
       subset: subset,
       buffered_transactions: [],
       slots: %{},
       slot_time: startup_date,
       slot_interval: slot_interval
     }}
  end

  def handle_cast({:add_transaction, address, timestamp}, state) do
    Logger.debug("Transaction #{Base.encode16(address)} added to the beacon chain (subset #{state.subset |> Base.encode16})")

    {:noreply,
     Map.update!(
       state,
       :buffered_transactions,
       &(&1 ++ [{address, timestamp}])
     )}
  end

  def handle_info(:create_slot, state = %{buffered_transactions: [], slot_interval: interval}) do
    schedule_slot(interval)
    {:noreply, state}
  end

  def handle_info(
        :create_slot,
        state = %{buffered_transactions: txs, slot_time: slot_time, slot_interval: interval}
      ) do
    # TODO: use the sync seed from the node shared secrets
    tx =
      Transaction.from_node_seed(:beacon, %Data{
        content:
          Enum.map(txs, fn {address, timestamp} ->
            "#{timestamp} - #{address |> Base.encode16()}"
          end)
          |> Enum.join("\n")
      })

    new_state =
      state
      |> Map.put(:buffered_transactions, [])
      |> put_in([:slots, slot_time |> DateTime.to_unix()], tx)
      |> Map.put(:slot_time, DateTime.add(slot_time, interval))

    schedule_slot(interval)

    Logger.info("Beacon slot created")

    {:noreply, new_state}
  end

  def handle_call({:list_addresses, last_sync_date}, _, state = %{slots: slots}) do
    addresses = slots
    |> Enum.filter(fn {time, _} -> time <= last_sync_date end)
    |> Enum.map(fn {_, %Transaction{data: %{content: content}}} ->
      content
      |> String.split("\n")
      |> Enum.map(fn line ->
        [_, address] = String.split(line, " - ")
        Base.decode16!(address)
      end)
    end)
    |> Enum.flat_map(&(&1))

    {:reply, addresses, state}
  end

  defp schedule_slot(interval) do
    Process.send_after(self(), :create_slot, interval)
  end

  @spec add_transaction(binary(), integer()) :: :ok
  def add_transaction(address, timestamp) do
    address
    |> from_address()
    |> via_tuple
    |> GenServer.cast({:add_transaction, address, timestamp})
  end

  @spec addresses(binary(), integer()) :: list(binary())
  def addresses(subset, last_sync_date) do
    subset
    |> via_tuple
    |> GenServer.call({:list_addresses, last_sync_date})
  end

  defp via_tuple(subset) do
    {:via, Registry, {BeaconSubsetRegistry, subset}}
  end

  @spec from_address(binary()) :: binary()
  def from_address(address) do
    :binary.part(address, 1, 1)
  end
end
