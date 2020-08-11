defmodule Uniris.BeaconSlotTimer do
  @moduledoc false

  use GenServer

  alias Uniris.BeaconSubsetRegistry
  alias Uniris.BeaconSubsets
  alias Uniris.Utils

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec slot_interval() :: non_neg_integer()
  def slot_interval do
    GenServer.call(__MODULE__, :slot_interval)
  end

  @spec last_slot_time() :: DateTime.t()
  def last_slot_time do
    GenServer.call(__MODULE__, :last_slot_time)
  end

  def init(interval: interval, trigger_offset: trigger_offset) do
    Task.start(fn -> schedule_new_slot(next_slot(interval, trigger_offset)) end)

    {:ok,
     %{
       last_slot_time: Utils.truncate_datetime(DateTime.utc_now()),
       interval: interval,
       trigger_offset: trigger_offset
     }}
  end

  def handle_call(:last_slot_time, _from, state = %{last_slot_time: slot_time}) do
    {:reply, slot_time, state}
  end

  def handle_call(:slot_interval, _from, state = %{interval: interval}) do
    {:reply, interval, state}
  end

  def handle_info(
        :new_slot,
        state = %{
          interval: interval,
          trigger_offset: trigger_offset
        }
      ) do
    Task.start(fn -> schedule_new_slot(next_slot(interval, trigger_offset)) end)

    slot_time = DateTime.utc_now()

    BeaconSubsets.all()
    |> Enum.each(fn subset ->
      [{pid, _}] = Registry.lookup(BeaconSubsetRegistry, subset)
      send(pid, {:create_slot, slot_time})
    end)

    {:noreply, Map.put(state, :last_slot_time, slot_time)}
  end

  defp schedule_new_slot(interval) when is_integer(interval) and interval >= 0 do
    Process.send_after(__MODULE__, :new_slot, interval * 1000)
  end

  defp next_slot(interval, trigger_offset) do
    if Utils.time_offset(interval) - trigger_offset <= 0 do
      Process.sleep(Utils.time_offset(interval) * 1000)
      Utils.time_offset(interval) - trigger_offset
    else
      Utils.time_offset(interval) - trigger_offset
    end
  end
end
