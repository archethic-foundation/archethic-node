defmodule Uniris.SelfRepair.Scheduler do
  @moduledoc """
  Process responsible of the self repair mechanism by pulling for each interval the last out of sync beacon chain slots
  by downloading the missing transactions and node updates
  """
  use GenServer

  alias Uniris.SelfRepair.Sync

  alias Uniris.Utils

  require Logger

  @doc """
  Start the scheduler process

  Options:
  - interval: Cron like interval to define when the self-repair/sync will occur
  """
  @spec start_link(args :: [interval: String.t()], opts :: Keyword.t()) :: {:ok, pid()}
  def start_link(args \\ [], opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @doc """
  Start the self repair synchronization scheduler
  """
  @spec start_scheduler(network_patch :: binary()) :: :ok
  def start_scheduler(patch) when is_binary(patch) do
    GenServer.call(__MODULE__, {:start_sync, patch})
  end

  @doc false
  def start_scheduler(pid, patch) when is_pid(pid) and is_binary(patch) do
    GenServer.call(pid, {:start_sync, patch})
  end

  def init(opts) do
    interval = Keyword.get(opts, :interval)

    {:ok,
     %{
       interval: interval,
       last_sync_date: Sync.last_sync_date()
     }}
  end

  def handle_call({:start_sync, patch}, _from, state = %{interval: interval}) do
    Logger.info("Start the Self-Repair scheduler")

    me = self()

    Task.start(fn ->
      timer = schedule_sync(me, Utils.time_offset(interval))
      remaining_seconds = remaining_seconds_from_timer(timer)

      Logger.info(
        "Self-Repair will be started in #{HumanizeTime.format_seconds(remaining_seconds)}"
      )
    end)

    new_state =
      state
      |> Map.put(:last_sync_date, Sync.last_sync_date())
      |> Map.put(:patch, patch)

    {:reply, :ok, new_state}
  end

  def handle_info(
        :sync,
        state = %{
          interval: interval,
          last_sync_date: last_sync_date,
          patch: patch
        }
      ) do
    Logger.info(
      "Self-Repair synchronization started from #{last_sync_date_to_string(last_sync_date)}"
    )

    Task.start(fn ->
      Sync.load_missed_transactions(last_sync_date, patch)
    end)

    me = self()

    Task.start(fn ->
      timer = schedule_sync(me, Utils.time_offset(interval))
      remaining_seconds = remaining_seconds_from_timer(timer)

      Logger.info(
        "Self-Repair will be started in #{HumanizeTime.format_seconds(remaining_seconds)}"
      )
    end)

    {:noreply, Map.put(state, :last_sync_date, update_last_sync_date()), :hibernate}
  end

  defp update_last_sync_date do
    next_sync_date = Utils.truncate_datetime(DateTime.utc_now())
    :ok = Sync.store_last_sync_date(next_sync_date)
    next_sync_date
  end

  defp schedule_sync(pid, interval) do
    Process.send_after(pid, :sync, interval * 1000)
  end

  defp last_sync_date_to_string(last_sync_date) do
    last_sync_date
    |> Utils.truncate_datetime()
    |> DateTime.to_string()
  end

  defp remaining_seconds_from_timer(timer) do
    case Process.read_timer(timer) do
      false ->
        0

      milliseconds ->
        div(milliseconds, 1000)
    end
  end
end
