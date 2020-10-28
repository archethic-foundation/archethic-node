defmodule Uniris.BeaconChain.SlotTimer do
  @moduledoc """
  Handle the scheduling of the beacon slots creation
  """

  use GenServer

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.Scheduler, as: CronScheduler

  alias Uniris.BeaconChain
  alias Uniris.BeaconChain.SubsetRegistry
  alias Uniris.Utils

  require Logger

  @doc """
  Create a new slot timer
  """
  def start_link(args \\ [], opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @doc """
  Return the interval for the slots
  """
  @spec slot_interval() :: binary()
  def slot_interval do
    GenServer.call(__MODULE__, :slot_interval)
  end

  @doc false
  def slot_interval(pid) when is_pid(pid) do
    GenServer.call(pid, :slot_interval)
  end

  @doc """
  Give the next beacon chain slot using the `SlotTimer` interval
  """
  @spec next_slot(DateTime.t()) :: DateTime.t()
  def next_slot(date_from = %DateTime{}) do
    GenServer.call(__MODULE__, {:next_slot, date_from})
  end

  @doc false
  def next_slot(pid, date_from = %DateTime{}) when is_pid(pid) do
    GenServer.call(pid, {:next_slot, date_from})
  end

  @doc """
  Returns the list of previous slots from the given date
  """
  @spec previous_slots(DateTime.t()) :: list(DateTime.t())
  def previous_slots(date_from = %DateTime{}) do
    GenServer.call(__MODULE__, {:previous_slots, date_from})
  end

  @doc false
  def previous_slots(pid, date_from = %DateTime{}) when is_pid(pid) do
    GenServer.call(pid, {:previous_slots, date_from})
  end

  @doc false
  def init(opts) do
    interval = Keyword.get(opts, :interval)
    trigger_offset = Keyword.get(opts, :trigger_offset)

    me = self()
    Task.start(fn -> schedule_new_slot(next_slot_time(interval, trigger_offset), me) end)

    {:ok,
     %{
       interval: interval,
       trigger_offset: trigger_offset
     }}
  end

  @doc false
  def handle_call(:slot_interval, _from, state = %{interval: interval}) do
    {:reply, interval, state}
  end

  def handle_call({:next_slot, from_date}, _from, state = %{interval: interval}) do
    next_date =
      interval
      |> CronParser.parse!(true)
      |> CronScheduler.get_next_run_date!(DateTime.to_naive(from_date))
      |> DateTime.from_naive!("Etc/UTC")

    {:reply, next_date, state}
  end

  def handle_call({:previous_slots, from_date}, _from, state = %{interval: interval}) do
    previous_slots =
      interval
      |> CronParser.parse!(true)
      |> CronScheduler.get_previous_run_dates(DateTime.utc_now() |> DateTime.to_naive())
      |> Stream.take_while(fn datetime ->
        datetime
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.compare(from_date) == :gt
      end)
      |> Stream.map(&DateTime.from_naive!(&1, "Etc/UTC"))
      |> Enum.to_list()

    {:reply, previous_slots, state}
  end

  @doc false
  def handle_info(
        :new_slot,
        state = %{
          interval: interval,
          trigger_offset: trigger_offset
        }
      ) do
    me = self()
    Task.start(fn -> schedule_new_slot(next_slot_time(interval, trigger_offset), me) end)

    slot_time = DateTime.utc_now()

    Logger.info("Trigger beacon slots creation at #{slot_time_to_string(slot_time)}")

    Enum.each(BeaconChain.list_subsets(), fn subset ->
      [{pid, _}] = Registry.lookup(SubsetRegistry, subset)
      send(pid, {:create_slot, slot_time})
    end)

    {:noreply, state}
  end

  defp schedule_new_slot(interval, pid) when is_integer(interval) and interval >= 0 do
    Process.send_after(pid, :new_slot, interval * 1000)
  end

  defp next_slot_time(interval, trigger_offset) do
    if Utils.time_offset(interval) - trigger_offset <= 0 do
      Process.sleep(Utils.time_offset(interval) * 1000)
      Utils.time_offset(interval) - trigger_offset
    else
      Utils.time_offset(interval) - trigger_offset
    end
  end

  defp slot_time_to_string(slot_time) do
    slot_time
    |> Utils.truncate_datetime()
    |> DateTime.to_string()
  end
end
