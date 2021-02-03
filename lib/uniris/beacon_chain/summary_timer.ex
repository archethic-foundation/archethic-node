defmodule Uniris.BeaconChain.SummaryTimer do
  @moduledoc """
  Handle the scheduling of the beacon summaries creation
  """

  use GenServer

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.Scheduler, as: CronScheduler

  alias Uniris.BeaconChain
  alias Uniris.BeaconChain.SubsetRegistry
  alias Uniris.Utils

  require Logger

  @doc """
  Create a new summary timer
  """
  def start_link(args \\ [], opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @doc """
  Give the next beacon chain slot using the `SlotTimer` interval
  """
  @spec next_summary(DateTime.t()) :: DateTime.t()
  def next_summary(date_from = %DateTime{}) do
    GenServer.call(__MODULE__, {:next_summary, date_from})
  end

  @doc false
  def next_summary(pid, date_from = %DateTime{}) when is_pid(pid) do
    GenServer.call(pid, {:next_summary, date_from})
  end

  @doc """
  Returns the list of previous summaries times from the given date
  """
  @spec previous_summaries(DateTime.t()) :: list(DateTime.t())
  def previous_summaries(date_from = %DateTime{}) do
    GenServer.call(__MODULE__, {:previous_summaries, date_from})
  end

  @doc false
  def previous_summaries(pid, date_from = %DateTime{}) when is_pid(pid) do
    GenServer.call(pid, {:previous_summaries, date_from})
  end

  @doc """
  Return the previous summary time
  """
  @spec previous_summary(DateTime.t()) :: DateTime.t()
  def previous_summary(date_from = %DateTime{}) do
    GenServer.call(__MODULE__, {:previous_summary, date_from})
  end

  @doc false
  def previous_summary(pid, date_from = %DateTime{}) when is_pid(pid) do
    GenServer.call(pid, {:previous_summary, date_from})
  end

  @doc false
  def init(opts) do
    interval = Keyword.get(opts, :interval)
    schedule_new_summary(interval)
    {:ok, %{interval: interval}}
  end

  def handle_call(
        {:next_summary, from_date = %DateTime{microsecond: {0, 0}}},
        _from,
        state = %{interval: interval}
      ) do
    next_date =
      interval
      |> CronParser.parse!(true)
      |> CronScheduler.get_next_run_dates(DateTime.to_naive(from_date))
      |> Enum.at(1)
      |> DateTime.from_naive!("Etc/UTC")

    {:reply, next_date, state}
  end

  def handle_call({:next_summary, from_date = %DateTime{}}, _from, state = %{interval: interval}) do
    next_date =
      interval
      |> CronParser.parse!(true)
      |> CronScheduler.get_next_run_date!(DateTime.to_naive(from_date))
      |> DateTime.from_naive!("Etc/UTC")

    {:reply, next_date, state}
  end

  def handle_call(
        {:previous_summary, from_date = %DateTime{microsecond: {0, 0}}},
        _from,
        state = %{interval: interval}
      ) do
    previous_date =
      interval
      |> CronParser.parse!(true)
      |> CronScheduler.get_previous_run_dates(DateTime.to_naive(from_date))
      |> Enum.at(1)
      |> DateTime.from_naive!("Etc/UTC")

    {:reply, previous_date, state}
  end

  def handle_call(
        {:previous_summary, from_date = %DateTime{}},
        _from,
        state = %{interval: interval}
      ) do
    previous_date =
      interval
      |> CronParser.parse!(true)
      |> CronScheduler.get_previous_run_date!(DateTime.to_naive(from_date))
      |> DateTime.from_naive!("Etc/UTC")

    {:reply, previous_date, state}
  end

  def handle_call({:previous_summaries, from_date}, _from, state = %{interval: interval}) do
    previous_summaries =
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

    {:reply, previous_summaries, state}
  end

  @doc false
  def handle_info(:new_summary, state = %{interval: interval}) do
    schedule_new_summary(interval)

    summary_time = DateTime.utc_now() |> Utils.truncate_datetime()

    Logger.info("Trigger beacon summary creation at #{Utils.time_to_string(summary_time)}")

    Enum.each(BeaconChain.list_subsets(), fn subset ->
      [{pid, _}] = Registry.lookup(SubsetRegistry, subset)
      send(pid, {:create_summary, summary_time})
    end)

    {:noreply, state}
  end

  defp schedule_new_summary(interval) do
    Process.send_after(self(), :new_summary, Utils.time_offset(interval) * 1000)
  end
end
