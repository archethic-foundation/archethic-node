defmodule Archethic.BeaconChain.SlotTimer do
  @moduledoc """
  Handle the scheduling of the beacon slots creation
  """

  use GenServer
  @vsn Mix.Project.config()[:version]

  alias Archethic.BeaconChain.SummaryTimer

  alias Archethic.DB

  alias Archethic.PubSub

  alias Archethic.Utils

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.Scheduler, as: CronScheduler

  require Logger

  @slot_timer_ets :archethic_slot_timer

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
    get_interval() |> Utils.next_date(date_from)
  end

  @doc """
  Returns the previous slot from the given date
  """
  @spec previous_slot(DateTime.t()) :: DateTime.t()
  def previous_slot(date_from = %DateTime{}) do
    get_interval()
    |> CronParser.parse!(true)
    |> Utils.previous_date(date_from)
  end

  @doc """
  Return the previous slot times
  """
  @spec previous_slots(DateTime.t()) :: list(DateTime.t())
  def previous_slots(date_from) do
    get_interval()
    |> CronParser.parse!(true)
    |> CronScheduler.get_previous_run_dates(DateTime.utc_now() |> DateTime.to_naive())
    |> Stream.take_while(fn datetime ->
      datetime
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.compare(date_from) == :gt
    end)
    |> Stream.map(&DateTime.from_naive!(&1, "Etc/UTC"))
    |> Enum.to_list()
  end

  def get_time_interval(unit \\ :second) do
    now = DateTime.utc_now()
    DateTime.diff(next_slot(now), previous_slot(now), unit)
  end

  defp get_interval do
    [{_, interval}] = :ets.lookup(@slot_timer_ets, :interval)
    interval
  end

  @doc false
  def init(opts) do
    :ets.new(@slot_timer_ets, [:named_table, :public, read_concurrency: true])
    interval = Keyword.get(opts, :interval)
    :ets.insert(@slot_timer_ets, {:interval, interval})

    if Archethic.up?() do
      Logger.info("Slot Timer: Starting...")
      next_time = next_slot(DateTime.utc_now())

      {:ok, %{interval: interval, timer: schedule_new_slot(interval), next_time: next_time}}
    else
      Logger.info("Slot Timer:  Waiting for Node to complete Bootstrap.")

      Archethic.PubSub.register_to_node_status()
      {:ok, %{interval: interval}}
    end
  end

  def handle_info(:node_up, state = %{interval: interval}) do
    Logger.info("Slot Timer: Starting...")

    case Map.get(state, :timer, nil) do
      nil -> :ok
      timer -> Process.cancel_timer(timer)
    end

    new_state =
      state
      |> Map.put(:timer, schedule_new_slot(interval))
      |> Map.put(:next_time, next_slot(DateTime.utc_now()))

    {:noreply, new_state, :hibernate}
  end

  def handle_info(:node_down, %{interval: interval, timer: timer}) do
    Logger.info("Slot Timer: Stopping...")
    Process.cancel_timer(timer)
    {:noreply, %{interval: interval}, :hibernate}
  end

  def handle_info(:node_down, %{interval: interval}) do
    Logger.info("Slot Timer: Stopping...")
    {:noreply, %{interval: interval}, :hibernate}
  end

  def handle_info(
        :new_slot,
        state = %{
          interval: interval,
          next_time: next_time
        }
      ) do
    timer = schedule_new_slot(interval)

    slot_time = next_time

    if SummaryTimer.match_interval?(slot_time) do
      # We clean the previously stored summaries - The retention time is for a self repair cycle
      # as the aggregates will be handled for long term storage.
      DB.clear_beacon_summaries()
    end

    PubSub.notify_current_epoch_of_slot_timer(slot_time)

    next_time = next_slot(DateTime.utc_now())

    new_state =
      state
      |> Map.put(:timer, timer)
      |> Map.put(:next_time, next_time)

    {:noreply, new_state, :hibernate}
  end

  def handle_cast({:new_conf, conf}, state) do
    case Keyword.get(conf, :interval) do
      nil ->
        {:noreply, state}

      new_interval ->
        :ets.insert(@slot_timer_ets, {:interval, new_interval})
        {:noreply, Map.put(state, :interval, new_interval)}
    end
  end

  defp schedule_new_slot(interval) do
    Process.send_after(self(), :new_slot, Utils.time_offset(interval))
  end

  def config_change(nil), do: :ok

  def config_change(conf) do
    GenServer.cast(__MODULE__, {:new_conf, conf})
  end
end
