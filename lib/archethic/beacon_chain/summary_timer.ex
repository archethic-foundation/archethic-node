defmodule Archethic.BeaconChain.SummaryTimer do
  @moduledoc """
  Handle the scheduling of the beacon summaries creation
  """

  use GenServer
  @vsn 2

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.DateChecker
  alias Crontab.Scheduler, as: CronScheduler

  alias Archethic.PubSub
  alias Archethic.Utils

  @doc """
  Create a new summary timer
  """
  def start_link(args \\ [], opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @doc """
  Give the next beacon chain slot using the `SummaryTimer` interval

  ## Examples

      iex> SummaryTimer.next_summary(~U[2021-01-02 03:00:19.501Z], "0 * * * * * *")
      ~U[2021-01-02 03:01:00Z]
  """
  @spec next_summary(date_from :: DateTime.t(), cron_interval :: binary()) :: DateTime.t()
  def next_summary(date_from = %DateTime{}, cron_interval \\ get_interval()) do
    Utils.next_date(cron_interval, date_from)
  end

  @doc """
  Returns the list of previous summaries times from the given date

  ## Examples

      iex> SummaryTimer.previous_summary(~U[2020-09-10 12:30:30Z], "* * * * * * *")
      ~U[2020-09-10 12:30:29Z]
  """
  @spec previous_summary(date_from :: DateTime.t(), cron_interval :: binary()) :: DateTime.t()
  def previous_summary(date_from = %DateTime{}, cron_interval \\ get_interval()) do
    cron_interval
    |> CronParser.parse!(true)
    |> Utils.previous_date(date_from)
  end

  @doc """
  Return the previous summary times

  ## Examples

    iex> SummaryTimer.previous_summaries(~U[2020-09-10 12:30:27Z], ~U[2020-09-10 12:30:30Z], "* * * * * * *")
    [
      ~U[2020-09-10 12:30:30Z],
      ~U[2020-09-10 12:30:29Z],
      ~U[2020-09-10 12:30:28Z]
    ]
  """
  @spec previous_summaries(from :: DateTime.t(), to :: DateTime.t(), cron_interval :: binary()) ::
          list(DateTime.t())
  def previous_summaries(
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
  Return the next summary times

  ## Examples

    iex> ~U[2020-09-10 12:30:26Z]
    ...> |> SummaryTimer.next_summaries(~U[2020-09-10 12:30:30Z], "* * * * * * *")
    ...> |> Enum.to_list()
    [
      ~U[2020-09-10 12:30:27Z],
      ~U[2020-09-10 12:30:28Z],
      ~U[2020-09-10 12:30:29Z]
    ]
  """
  @spec next_summaries(from :: DateTime.t(), to :: DateTime.t(), cron_interval :: binary()) ::
          Enumerable.t() | list(DateTime.t())
  def next_summaries(
        date_from = %DateTime{},
        date_to = %DateTime{} \\ DateTime.utc_now(),
        cron_interval \\ get_interval()
      ) do
    cron_interval
    |> CronParser.parse!(true)
    |> CronScheduler.get_next_run_dates(date_from |> DateTime.to_naive())
    |> Stream.reject(&(DateTime.compare(DateTime.from_naive!(&1, "Etc/UTC"), date_from) == :eq))
    |> Stream.take_while(fn datetime ->
      datetime
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.compare(date_to) == :lt
    end)
    |> Stream.map(&DateTime.from_naive!(&1, "Etc/UTC"))
  end

  @doc """
  Determine if the given date matches the summary's interval

  ## Examples

      iex> SummaryTimer.match_interval?(~U[2021-02-03 13:00:00Z], "0 * * * * * *")
      true

      iex> SummaryTimer.match_interval?(~U[2021-02-03 13:00:50Z], "0 * * * * * *")
      false
  """
  @spec match_interval?(date :: DateTime.t(), cron_interval :: binary()) :: boolean()
  def match_interval?(date = %DateTime{}, cron_interval \\ get_interval()) do
    cron_interval
    |> CronParser.parse!(true)
    |> DateChecker.matches_date?(DateTime.to_naive(date))
  end

  @doc false
  def init(_) do
    schedule_next_summary_time(get_interval())
    {:ok, %{}, :hibernate}
  end

  @doc """
  Return the summary timer cron interval
  """
  def get_interval do
    :archethic
    |> Application.get_env(__MODULE__, [])
    |> Keyword.fetch!(:interval)
  end

  def handle_info(
        :next_summary_time,
        state
      ) do
    timer = schedule_next_summary_time(get_interval())

    DateTime.utc_now()
    |> Utils.truncate_datetime()
    |> next_summary()
    |> PubSub.notify_next_summary_time()

    {:noreply, Map.put(state, :timer, timer), :hibernate}
  end

  def code_change(1, state, _) do
    :ets.delete(:archethic_summary_timer)
    {:ok, Map.delete(state, :interval)}
  end

  defp schedule_next_summary_time(interval) do
    Process.send_after(self(), :next_summary_time, Utils.time_offset(interval))
  end
end
