defmodule Uniris.SelfRepair.Scheduler do
  @moduledoc """
  Process responsible of the self repair mechanism by pulling for each interval the last out of sync beacon chain slots
  by downloading the missing transactions and node updates
  """
  use GenServer

  alias Uniris.P2P
  alias Uniris.P2P.Node

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
  @spec start_scheduler(DateTime.t()) :: :ok
  def start_scheduler(last_date_sync = %DateTime{}) do
    GenServer.call(__MODULE__, {:start, last_date_sync})
  end

  @doc false
  def start_scheduler(pid, last_date_sync = %DateTime{}) when is_pid(pid) do
    GenServer.call(pid, {:start, last_date_sync})
  end

  def init(opts) do
    interval = Keyword.get(opts, :interval)

    {:ok, %{interval: interval}}
  end

  def handle_call({:start, last_sync_date}, _from, state = %{interval: interval}) do
    Logger.info("Self-Repair scheduler is started")

    case Map.get(state, :timer) do
      nil ->
        :ok

      timer ->
        Process.cancel_timer(timer)
    end

    timer = schedule_sync(interval)
    remaining_seconds = remaining_seconds_from_timer(timer)

    Logger.info(
      "Next Self-Repair Sync will be started in #{HumanizeTime.format_seconds(remaining_seconds)}"
    )

    new_state =
      state
      |> Map.put(:last_sync_date, last_sync_date)
      |> Map.put(:timer, timer)

    {:reply, :ok, new_state}
  end

  def handle_info(
        :sync,
        state = %{
          interval: interval,
          last_sync_date: last_sync_date
        }
      ) do
    Logger.info(
      "Self-Repair synchronization started from #{last_sync_date_to_string(last_sync_date)}"
    )

    Task.start(fn ->
      Sync.load_missed_transactions(last_sync_date, get_node_patch())
    end)

    timer = schedule_sync(interval)
    remaining_seconds = remaining_seconds_from_timer(timer)

    Logger.info(
      "Self-Repair will be started in #{HumanizeTime.format_seconds(remaining_seconds)}"
    )

    {:noreply, Map.put(state, :last_sync_date, update_last_sync_date()), :hibernate}
  end

  defp get_node_patch do
    %Node{network_patch: network_patch} = P2P.get_node_info()
    network_patch
  end

  defp update_last_sync_date do
    next_sync_date = Utils.truncate_datetime(DateTime.utc_now())
    :ok = Sync.store_last_sync_date(next_sync_date)
    next_sync_date
  end

  defp schedule_sync(interval) do
    Process.send_after(self(), :sync, Utils.time_offset(interval) * 1000)
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
