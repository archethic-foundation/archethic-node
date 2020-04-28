defmodule UnirisCore.BeaconSlotTimer do
  @moduledoc false

  use GenServer

  alias UnirisCore.Utils
  alias UnirisCore.BeaconSubsets
  alias UnirisCore.BeaconSubsetRegistry

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_scheduling() do
    GenServer.call(__MODULE__, :start_scheduling)
  end

  def slot_interval() do
    GenServer.call(__MODULE__, :slot_interval)
  end

  def init(opts) do
    interval = Keyword.get(opts, :slot_interval)
    {:ok, %{last_slot_time: DateTime.utc_now(), interval: interval}}
  end

  def handle_call(:start_scheduling, _from, state = %{interval: interval}) do
    schedule_new_slot(Utils.time_offset(interval))
    {:reply, :ok, state}
  end

  def handle_call(:last_slot_time, _from, state = %{last_slot_time: slot_time}) do
    {:reply, slot_time, state}
  end

  def handle_call(:slot_interval, _from, state = %{interval: interval}) do
    {:reply, interval, state}
  end

  def handle_info(:new_slot, state) do
    slot_time = DateTime.utc_now()

    BeaconSubsets.all()
    |> Enum.each(fn subset ->
      [{pid, _}] = Registry.lookup(BeaconSubsetRegistry, subset)
      send(pid, {:create_slot, slot_time})
    end)

    {:noreply, Map.put(state, :last_slot_time, slot_time)}
  end

  defp schedule_new_slot(interval) do
    Process.send_after(__MODULE__, :new_slot, interval)
  end

  def last_slot_time() do
    GenServer.call(__MODULE__, :last_slot_time)
  end
end
