defmodule Uniris.BeaconSlotTimer do
  @moduledoc """
  Handle the scheduling of the beacon slots creation
  """

  use GenServer

  alias Uniris.Beacon
  alias Uniris.BeaconSubsetRegistry
  alias Uniris.Utils

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Return the interval for the slots
  """
  @spec slot_interval() :: non_neg_integer()
  def slot_interval do
    GenServer.call(__MODULE__, :slot_interval)
  end

  def init(interval: interval, trigger_offset: trigger_offset) do
    Task.start(fn -> schedule_new_slot(next_slot(interval, trigger_offset)) end)

    {:ok,
     %{
       interval: interval,
       trigger_offset: trigger_offset
     }}
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

    Beacon.list_subsets()
    |> Enum.each(fn subset ->
      [{pid, _}] = Registry.lookup(BeaconSubsetRegistry, subset)
      send(pid, {:create_slot, slot_time})
    end)

    {:noreply, state}
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
