defmodule Uniris.BeaconChain.SummaryTimer do
  @moduledoc """
  Handle the scheduling of the beacon summaries creation
  """

  use GenServer

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.Scheduler, as: CronScheduler

  alias Uniris.BeaconChain
  alias Uniris.BeaconChain.SubsetRegistry

  alias Uniris.Crypto

  alias Uniris.PubSub
  alias Uniris.P2P.Node

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
  def next_summary(date_from = %DateTime{microsecond: {0, 0}}) do
    get_interval()
    |> CronParser.parse!(true)
    |> CronScheduler.get_next_run_dates(DateTime.to_naive(date_from))
    |> Enum.at(1)
    |> DateTime.from_naive!("Etc/UTC")
  end

  def next_summary(date_from = %DateTime{}) do
    get_interval()
    |> CronParser.parse!(true)
    |> CronScheduler.get_next_run_date!(DateTime.to_naive(date_from))
    |> DateTime.from_naive!("Etc/UTC")
  end

  @doc """
  Returns the list of previous summaries times from the given date
  """
  @spec previous_summary(DateTime.t()) :: DateTime.t()
  def previous_summary(date_from = %DateTime{microsecond: {0, 0}}) do
    get_interval()
    |> CronParser.parse!(true)
    |> CronScheduler.get_previous_run_dates(DateTime.to_naive(date_from))
    |> Enum.at(1)
    |> DateTime.from_naive!("Etc/UTC")
  end

  def previous_summary(date_from = %DateTime{}) do
    get_interval()
    |> CronParser.parse!(true)
    |> CronScheduler.get_previous_run_date!(DateTime.to_naive(date_from))
    |> DateTime.from_naive!("Etc/UTC")
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
  Start the scheduler
  """
  @spec start_scheduler() :: :ok
  def start_scheduler, do: GenServer.cast(__MODULE__, :start_scheduler)

  @doc false
  def start_scheduler(pid), do: GenServer.cast(pid, :start_scheduler)

  @doc false
  def init(opts) do
    interval = Keyword.get(opts, :interval)
    :ets.new(:uniris_summary_timer, [:named_table, :public, read_concurrency: true])
    :ets.insert(:uniris_summary_timer, {:interval, interval})

    PubSub.register_to_node_update()

    {:ok, %{interval: interval}, :hibernate}
  end

  defp get_interval do
    [{_, interval}] = :ets.lookup(:uniris_summary_timer, :interval)
    interval
  end

  @doc false
  def handle_info(
        {:node_update, %Node{authorized?: true, first_public_key: key}},
        state = %{interval: interval}
      ) do
    if key == Crypto.node_public_key() do
      state
      |> Map.get(:timer)
      |> cancel_timer()

      timer = schedule_new_summary(interval)
      {:noreply, Map.put(state, :timer, timer), :hibernate}
    else
      {:noreply, state}
    end
  end

  def handle_info({:node_update, %Node{authorized?: false, first_public_key: key}}, state) do
    if key == Crypto.node_public_key() do
      state
      |> Map.get(:timer)
      |> cancel_timer()

      {:noreply, Map.delete(state, :timer), :hibernate}
    else
      {:noreply, state}
    end
  end

  def handle_info(:new_summary, state = %{interval: interval}) do
    timer = schedule_new_summary(interval)

    summary_time = DateTime.utc_now() |> Utils.truncate_datetime()

    Logger.debug("Trigger beacon summary creation at #{Utils.time_to_string(summary_time)}")

    Enum.each(BeaconChain.list_subsets(), fn subset ->
      [{pid, _}] = Registry.lookup(SubsetRegistry, subset)
      send(pid, {:create_summary, summary_time})
    end)

    {:noreply, Map.put(state, :timer, timer), :hibernate}
  end

  defp schedule_new_summary(interval) do
    Process.send_after(self(), :new_summary, Utils.time_offset(interval) * 1000)
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)
end
