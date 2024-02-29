defmodule Archethic.BeaconChain.SlotTimer do
  @moduledoc """
  Handle the scheduling of the beacon slots creation
  """

  use GenServer
  @vsn 2

  alias Archethic.BeaconChain.SummaryTimer

  alias Archethic.DB

  alias Archethic.PubSub

  alias Archethic.Utils

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.Scheduler, as: CronScheduler

  require Logger

  @doc """
  Create a new slot timer
  """
  def start_link(args \\ [], opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @doc """
  Give the next beacon chain slot using the `SlotTimer` interval

  ## Examples

      iex> SlotTimer.next_slot(~U[2021-01-02 03:00:10Z], "*/10 * * * * * *")
      ~U[2021-01-02 03:00:20Z]
  """
  @spec next_slot(date_from :: DateTime.t(), cron_interval :: binary()) :: DateTime.t()
  def next_slot(date_from = %DateTime{}, cron_interval \\ get_interval()) do
    Utils.next_date(cron_interval, date_from)
  end

  @doc """
  Returns the previous slot from the given date

  ## Examples

      iex> SlotTimer.previous_slot(~U[2021-01-02 03:00:10Z], "*/10 * * * * * *")
      ~U[2021-01-02 03:00:00Z]
  """
  @spec previous_slot(date_from :: DateTime.t(), cron_interval :: binary()) :: DateTime.t()
  def previous_slot(date_from = %DateTime{}, cron_interval \\ get_interval()) do
    cron_interval
    |> CronParser.parse!(true)
    |> Utils.previous_date(date_from)
  end

  @doc """
  Return the previous slot times

  ## Examples

      iex> SlotTimer.previous_slots(~U[2021-01-02 03:00:00Z], ~U[2021-01-02 03:00:30Z], "*/10 * * * * * *")
      [
        ~U[2021-01-02 03:00:30Z],
        ~U[2021-01-02 03:00:20Z],
        ~U[2021-01-02 03:00:10Z]
      ]
  """
  @spec previous_slots(date_from :: DateTime.t(), cron_interval :: binary()) :: list(DateTime.t())
  def previous_slots(
        date_from = %DateTime{},
        date_to = %DateTime{} \\ DateTime.utc_now(),
        cron_interval \\ get_interval()
      ) do
    cron_interval
    |> CronParser.parse!(true)
    |> CronScheduler.get_previous_run_dates(DateTime.to_naive(date_to))
    |> Stream.take_while(fn datetime ->
      datetime
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.compare(date_from) == :gt
    end)
    |> Stream.map(&DateTime.from_naive!(&1, "Etc/UTC"))
    |> Enum.to_list()
  end

  @doc """
  Returns time interval between next and previous slot

  ## Examples

      iex> SlotTimer.get_time_interval(~U[2021-01-02 03:00:00Z], "*/10 * * * * * *")
      20
  """
  @spec get_time_interval(
          date_from :: DateTime.t(),
          cron_interval :: binary(),
          unit :: System.time_unit()
        ) ::
          non_neg_integer()
  def get_time_interval(
        date_from = %DateTime{} \\ DateTime.utc_now(),
        cron_interval \\ get_interval(),
        unit \\ :second
      ) do
    DateTime.diff(
      next_slot(date_from, cron_interval),
      previous_slot(date_from, cron_interval),
      unit
    )
  end

  @doc """
  Return the slot timer cron interval
  """
  @spec get_interval() :: binary()
  def get_interval do
    :archethic
    |> Application.get_env(__MODULE__, [])
    |> Keyword.fetch!(:interval)
  end

  @doc false
  def init(_) do
    if Archethic.up?() do
      Logger.info("Slot Timer: Starting...")
      next_time = next_slot(DateTime.utc_now())

      {:ok, %{timer: schedule_new_slot(get_interval()), next_time: next_time}}
    else
      Logger.info("Slot Timer:  Waiting for Node to complete Bootstrap.")

      Archethic.PubSub.register_to_node_status()
      {:ok, %{}}
    end
  end

  def handle_info(:node_up, state) do
    Logger.info("Slot Timer: Starting...")

    case Map.get(state, :timer, nil) do
      nil -> :ok
      timer -> Process.cancel_timer(timer)
    end

    new_state =
      state
      |> Map.put(:timer, schedule_new_slot(get_interval()))
      |> Map.put(:next_time, next_slot(DateTime.utc_now()))

    {:noreply, new_state, :hibernate}
  end

  def handle_info(:node_down, %{timer: timer}) do
    Logger.info("Slot Timer: Stopping...")
    Process.cancel_timer(timer)
    {:noreply, %{}, :hibernate}
  end

  def handle_info(:node_down, _state) do
    Logger.info("Slot Timer: Stopping...")
    {:noreply, %{}, :hibernate}
  end

  def handle_info(
        :new_slot,
        state = %{
          next_time: next_time
        }
      ) do
    timer = schedule_new_slot(get_interval())

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

  def code_change(1, state, _) do 
    :ets.delete(:archethic_slot_timer)
    {:ok, Map.delete(state, :interval) }
  end

  defp schedule_new_slot(interval) do
    Process.send_after(self(), :new_slot, Utils.time_offset(interval))
  end
end
