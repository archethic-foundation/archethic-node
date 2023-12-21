defmodule Archethic.BeaconChain.SummaryTimer do
  @moduledoc """
  Handle the scheduling of the beacon summaries creation
  """

  use GenServer
  @vsn Mix.Project.config()[:version]

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
  """
  @spec next_summary(DateTime.t()) :: DateTime.t()
  def next_summary(date_from = %DateTime{}) do
    get_interval() |> Utils.next_date(date_from)
  end

  @doc """
  Returns the list of previous summaries times from the given date
  """
  @spec previous_summary(DateTime.t()) :: DateTime.t()
  def previous_summary(date_from = %DateTime{}) do
    get_interval()
    |> CronParser.parse!(true)
    |> Utils.previous_date(date_from)
  end

  @doc """
  Return the previous summary time
  """
  @spec previous_summaries(DateTime.t()) :: list(DateTime.t())
  def previous_summaries(date_from = %DateTime{}) do
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

  @doc """
  Return the next summary times from a date until now
  """
  @spec next_summaries(from :: DateTime.t(), to :: DateTime.t()) ::
          Enumerable.t() | list(DateTime.t())
  def next_summaries(date_from = %DateTime{}, date_to = %DateTime{} \\ DateTime.utc_now()) do
    get_interval()
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
  """
  @spec match_interval?(DateTime.t()) :: boolean()
  def match_interval?(date = %DateTime{}) do
    get_interval()
    |> CronParser.parse!(true)
    |> DateChecker.matches_date?(DateTime.to_naive(date))
  end

  @doc false
  def init(opts) do
    interval = Keyword.get(opts, :interval)
    :ets.new(:archethic_summary_timer, [:named_table, :public, read_concurrency: true])
    :ets.insert(:archethic_summary_timer, {:interval, interval})
    schedule_next_summary_time(interval)
    {:ok, %{interval: interval}, :hibernate}
  end

  defp get_interval do
    [{_, interval}] = :ets.lookup(:archethic_summary_timer, :interval)
    interval
  end

  def handle_cast({:new_conf, conf}, state) do
    case Keyword.get(conf, :interval) do
      nil ->
        {:noreply, state}

      new_interval ->
        :ets.insert(:archethic_summary_timer, {:interval, new_interval})
        {:noreply, Map.put(state, :interval, new_interval)}
    end
  end

  def handle_info(
        :next_summary_time,
        state = %{
          interval: interval
        }
      ) do
    timer = schedule_next_summary_time(interval)

    slot_time = DateTime.utc_now() |> Utils.truncate_datetime()

    PubSub.notify_next_summary_time(next_summary(slot_time))
    {:noreply, Map.put(state, :timer, timer), :hibernate}
  end

  defp schedule_next_summary_time(interval) do
    Process.send_after(self(), :next_summary_time, Utils.time_offset(interval))
  end

  def config_change(nil), do: :ok

  def config_change(conf) do
    GenServer.cast(__MODULE__, {:new_conf, conf})
  end
end
