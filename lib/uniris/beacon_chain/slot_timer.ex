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
  Returns the previous slot from the given date
  """
  @spec previous_slot(DateTime.t()) :: DateTime.t()
  def previous_slot(date_from = %DateTime{}) do
    GenServer.call(__MODULE__, {:previous_slot, date_from})
  end

  @doc false
  def previous_slot(pid, date_from = %DateTime{}) when is_pid(pid) do
    GenServer.call(pid, {:previous_slot, date_from})
  end

  @doc false
  def init(opts) do
    interval = Keyword.get(opts, :interval)

    schedule_new_slot(interval)
    {:ok, %{interval: interval}}
  end

  def handle_call({:next_slot, from_date}, _from, state = %{interval: interval}) do
    next_date =
      interval
      |> CronParser.parse!(true)
      |> CronScheduler.get_next_run_date!(DateTime.to_naive(from_date))
      |> DateTime.from_naive!("Etc/UTC")

    {:reply, next_date, state}
  end

  def handle_call({:previous_slot, from_date}, _from, state = %{interval: interval}) do
    previous_slot =
      interval
      |> CronParser.parse!(true)
      |> CronScheduler.get_previous_run_date!(DateTime.to_naive(from_date))
      |> DateTime.from_naive!("Etc/UTC")

    {:reply, previous_slot, state}
  end

  @doc false
  def handle_info(
        :new_slot,
        state = %{
          interval: interval
        }
      ) do
    schedule_new_slot(interval)

    slot_time = DateTime.utc_now() |> Utils.truncate_datetime()

    Logger.info("Trigger beacon slots creation at #{Utils.time_to_string(slot_time)}")

    Enum.each(BeaconChain.list_subsets(), fn subset ->
      [{pid, _}] = Registry.lookup(SubsetRegistry, subset)
      send(pid, {:create_slot, slot_time})
    end)

    {:noreply, state}
  end

  defp schedule_new_slot(interval) do
    Process.send_after(self(), :new_slot, Utils.time_offset(interval) * 1000)
  end
end
