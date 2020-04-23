defmodule UnirisCore.BeaconSlotTimer do
  @moduledoc false

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    slot_interval = Keyword.get(opts, :slot_interval)
    schedule_new_slot_time(slot_interval)
    {:ok, %{last_slot_time: DateTime.utc_now(), slot_interval: slot_interval}}
  end

  def handle_info(:increase_slot_time, state) do
    {:noreply, Map.put(state, :last_slot_time, DateTime.utc_now())}
  end

  def handle_call(:last_slot_time, _from, state = %{last_slot_time: slot_time}) do
    {:reply, slot_time, state}
  end

  def handle_call(:slot_interval, _from, state = %{slot_interval: slot_interval}) do
    {:reply, slot_interval, state}
  end

  defp schedule_new_slot_time(interval) do
    Process.send_after(__MODULE__, :increase_slot_time, interval)
  end

  def slot_interval() do
    GenServer.call(__MODULE__, :slot_interval)
  end

  def last_slot_time() do
    GenServer.call(__MODULE__, :last_slot_time)
  end
end
