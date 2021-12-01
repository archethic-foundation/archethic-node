defmodule ArchEthic.SelfRepair.Scheduler do
  @moduledoc """
  Process responsible of the self repair mechanism by pulling for each interval the last out of sync beacon chain slots
  by downloading the missing transactions and node updates
  """
  use GenServer

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node

  alias ArchEthic.SelfRepair.Sync

  alias ArchEthic.TaskSupervisor

  alias ArchEthic.Utils

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
  @spec start_scheduler() :: :ok
  def start_scheduler do
    GenServer.call(__MODULE__, :start)
  end

  @doc false
  def start_scheduler(pid) when is_pid(pid) do
    GenServer.call(pid, :start)
  end

  def init(opts) do
    interval = Keyword.get(opts, :interval)

    {:ok, %{interval: interval}}
  end

  def handle_call(:start, _from, state = %{interval: interval}) do
    Logger.info("Self-Repair scheduler is started")

    case Map.get(state, :timer) do
      nil ->
        :ok

      timer ->
        Process.cancel_timer(timer)
    end

    timer = schedule_sync(interval)

    Logger.info(
      "Next Self-Repair Sync will be started in #{Utils.remaining_seconds_from_timer(timer)}"
    )

    new_state =
      state
      |> Map.put(:timer, timer)

    {:reply, :ok, new_state}
  end

  def handle_call(:get_interval, _, state = %{interval: interval}) do
    {:reply, interval, state}
  end

  def handle_info(
        :sync,
        state = %{
          interval: interval
        }
      ) do
    last_sync_date = Sync.last_sync_date()

    Logger.info(
      "Self-Repair synchronization started from #{last_sync_date_to_string(last_sync_date)}"
    )

    Task.Supervisor.start_child(TaskSupervisor, fn ->
      Sync.load_missed_transactions(last_sync_date, get_node_patch())
    end)

    timer = schedule_sync(interval)
    Logger.info("Self-Repair will be started in #{Utils.remaining_seconds_from_timer(timer)}")

    update_last_sync_date()

    new_state =
      state
      |> Map.put(:timer, timer)

    {:noreply, new_state, :hibernate}
  end

  def handle_cast({:new_conf, conf}, state) do
    case Keyword.get(conf, :interval) do
      nil ->
        {:noreply, state}

      new_interval ->
        {:noreply, Map.put(state, :interval, new_interval)}
    end
  end

  defp get_node_patch do
    %Node{network_patch: network_patch} = P2P.get_node_info()
    network_patch
  end

  defp update_last_sync_date do
    next_sync_date = Utils.truncate_datetime(DateTime.utc_now())
    :ok = Sync.store_last_sync_date(next_sync_date)
  end

  defp schedule_sync(interval) do
    Process.send_after(self(), :sync, Utils.time_offset(interval) * 1000)
  end

  defp last_sync_date_to_string(last_sync_date) do
    last_sync_date
    |> Utils.truncate_datetime()
    |> DateTime.to_string()
  end

  def config_change(nil), do: :ok

  def config_change(new_conf) do
    GenServer.cast(__MODULE__, {:new_conf, new_conf})
  end

  @doc """
  Retrieve the self repair interval
  """
  @spec get_interval() :: binary()
  def get_interval do
    GenServer.call(__MODULE__, :get_interval)
  end
end
