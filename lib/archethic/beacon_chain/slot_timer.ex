defmodule Archethic.BeaconChain.SlotTimer do
  @moduledoc """
  Handle the scheduling of the beacon slots creation
  """

  use GenServer

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.SubsetRegistry
  alias Archethic.BeaconChain.SummaryTimer

  alias Archethic.DB

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Node
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
    cron_expression = CronParser.parse!(get_interval(), true)
    naive_date_from = DateTime.to_naive(date_from)

    if Crontab.DateChecker.matches_date?(cron_expression, naive_date_from) do
      case date_from do
        %DateTime{microsecond: {0, _}} ->
          cron_expression
          |> CronScheduler.get_next_run_dates(naive_date_from)
          |> Enum.at(1)
          |> DateTime.from_naive!("Etc/UTC")

        _ ->
          cron_expression
          |> CronScheduler.get_next_run_date!(naive_date_from)
          |> DateTime.from_naive!("Etc/UTC")
      end
    else
      cron_expression
      |> CronScheduler.get_next_run_date!(naive_date_from)
      |> DateTime.from_naive!("Etc/UTC")
    end
  end

  @doc """
  Returns the previous slot from the given date
  """
  @spec previous_slot(DateTime.t()) :: DateTime.t()
  def previous_slot(date_from = %DateTime{}) do
    cron_expression = CronParser.parse!(get_interval(), true)
    naive_date_from = DateTime.to_naive(date_from)

    if Crontab.DateChecker.matches_date?(cron_expression, naive_date_from) do
      case date_from do
        %DateTime{microsecond: {microsecond, _}} when microsecond > 0 ->
          DateTime.truncate(date_from, :second)

        _ ->
          cron_expression
          |> CronScheduler.get_previous_run_dates(naive_date_from)
          |> Enum.at(1)
          |> DateTime.from_naive!("Etc/UTC")
      end
    else
      cron_expression
      |> CronScheduler.get_previous_run_date!(naive_date_from)
      |> DateTime.from_naive!("Etc/UTC")
    end
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

    case :persistent_term.get(:archethic_up, nil) do
      nil ->
        Logger.info("Slot Timer:  Waiting for Node to complete Bootstrap.")

        Archethic.PubSub.register_to_node_up()
        {:ok, %{interval: interval}}

      :up ->
        Logger.info("Slot Timer: Starting...")
        next_time = next_slot(DateTime.utc_now() |> DateTime.truncate(:second))

        {:ok, %{interval: interval, timer: schedule_new_slot(interval), next_time: next_time}}
    end
  end

  def handle_info(:node_up, server_data = %{interval: interval}) do
    Logger.info("Slot Timer: Starting...")

    new_server_data =
      server_data
      |> Map.put(:timer, schedule_new_slot(interval))
      |> Map.put(:next_time, next_slot(DateTime.utc_now() |> DateTime.truncate(:second)))

    {:noreply, new_server_data, :hibernate}
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

    PubSub.notify_current_epoch_of_slot_timer(slot_time)

    if SummaryTimer.match_interval?(slot_time) do
      # We clean the previously stored summaries - The retention time is for a self repair cycle
      # as the aggregates will be handle for long term storage.
      DB.clear_beacon_summaries()
    end

    case Crypto.first_node_public_key() |> P2P.get_node_info() |> elem(1) do
      %Node{authorized?: true, available?: true} ->
        Logger.debug("Trigger beacon slots creation at #{Utils.time_to_string(slot_time)}")
        Enum.each(list_subset_processes(), &send(&1, {:create_slot, slot_time}))

      _ ->
        :skip
    end

    next_time = next_slot(next_time)

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

  defp list_subset_processes do
    BeaconChain.list_subsets()
    |> Enum.map(fn subset ->
      case Registry.lookup(SubsetRegistry, subset) do
        [{pid, _}] ->
          pid

        _ ->
          nil
      end
    end)
    |> Enum.filter(& &1)
  end

  defp schedule_new_slot(interval) do
    Process.send_after(self(), :new_slot, Utils.time_offset(interval) * 1000)
  end

  def config_change(nil), do: :ok

  def config_change(conf) do
    GenServer.cast(__MODULE__, {:new_conf, conf})
  end
end
