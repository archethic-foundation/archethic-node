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
    get_interval()
    |> CronParser.parse!(true)
    |> CronScheduler.get_next_run_date!(DateTime.to_naive(date_from))
    |> DateTime.from_naive!("Etc/UTC")
  end

  @doc """
  Returns the previous slot from the given date
  """
  @spec previous_slot(DateTime.t()) :: DateTime.t()
  def previous_slot(date_from = %DateTime{microsecond: {0, 0}}) do
    get_interval()
    |> CronParser.parse!(true)
    |> CronScheduler.get_previous_run_dates(DateTime.to_naive(date_from))
    |> Enum.at(1)
    |> DateTime.from_naive!("Etc/UTC")
  end

  def previous_slot(date_from = %DateTime{}) do
    get_interval()
    |> CronParser.parse!(true)
    |> CronScheduler.get_previous_run_date!(DateTime.to_naive(date_from))
    |> DateTime.from_naive!("Etc/UTC")
  end

  defp get_interval do
    [{_, interval}] = :ets.lookup(:uniris_slot_timer_timer, :interval)
    interval
  end

  @doc """
  Start the scheduler
  """
  @spec start_scheduler() :: :ok
  def start_scheduler, do: GenServer.cast(__MODULE__, :start_scheduler)

  @doc false
  def start_scheduler(pid), do: GenServer.cast(pid, :start_scheduler)

  @doc false
  def init(opts) do
    interval = Keyword.get(opts, :interval)
    :ets.new(:uniris_slot_timer_timer, [:named_table, :public, read_concurrency: true])
    :ets.insert(:uniris_slot_timer_timer, {:interval, interval})
    {:ok, %{interval: interval}}
  end

  def handle_cast(:start_scheduler, state = %{interval: interval}) do
    case Map.get(state, :timer) do
      nil ->
        :ok

      timer ->
        Process.cancel_timer(timer)
    end

    timer = schedule_new_slot(interval)
    {:noreply, Map.put(state, :timer, timer), :hibernate}
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

    {:noreply, state, :hibernate}
  end

  defp schedule_new_slot(interval) do
    Process.send_after(self(), :new_slot, Utils.time_offset(interval) * 1000)
  end
end
