defmodule Archethic.SelfRepair.Scheduler do
  @moduledoc """
  Process responsible of the self repair mechanism by pulling for each interval the last out of sync beacon chain slots
  by downloading the missing transactions and node updates
  """
  use GenServer
  @vsn Mix.Project.config()[:version]
  alias Archethic
  alias Archethic.{P2P, SelfRepair.Sync, TaskSupervisor, Utils, PubSub}

  alias Archethic.Bootstrap.Sync, as: BootstrapSync

  require Logger

  @max_retry_count 10

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
        state
      ) do
    last_sync_date = Sync.last_sync_date()

    Logger.info(
      "Self-Repair synchronization started from #{last_sync_date_to_string(last_sync_date)}"
    )

    Task.Supervisor.async_nolink(TaskSupervisor, fn ->
      # Loading transactions can take a lot of time to be achieve and can overpass an epoch.
      # So to avoid missing a beacon summary epoch, we save the starting date and update the last sync date with it
      # at the end of loading (in case there is a crash during self repair)
      Sync.load_missed_transactions(last_sync_date)
    end)

    {:noreply, state, :hibernate}
  end

  def handle_info({ref, :ok}, state = %{interval: interval}) do
    # If the node is still unavailable after self repair, we send the postpone the
    # end of node sync message
    timer = schedule_sync(interval)
    Logger.info("Self-Repair will be started in #{Utils.remaining_seconds_from_timer(timer)}")

    new_state =
      state
      |> Map.put(:timer, timer)
      |> Map.delete(:retry_count)

    if !Archethic.up?() do
      :persistent_term.put(:archethic_up, :up)
      PubSub.notify_node_status(:node_up)
    end

    if !P2P.available_node?(), do: BootstrapSync.publish_end_of_sync()
    Process.demonitor(ref, [:flush])
    {:noreply, new_state}
  end

  def handle_info({:DOWN, _ref, _, _, reason}, state = %{interval: interval}) do
    Logger.error("Failed to completed self-repair cycle: #{inspect(reason)}")

    if Archethic.up?() do
      :persistent_term.put(:archethic_up, :down)
      PubSub.notify_node_status(:node_down)
    end

    new_state = Map.update(state, :retry_count, 1, &(&1 + 1))

    new_state =
      if new_state.retry_count > @max_retry_count do
        timer = schedule_sync(interval)

        new_state
        |> Map.delete(:retry_count)
        |> Map.put(:timer, timer)
      else
        send(self(), :sync)
        new_state
      end

    {:noreply, new_state}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  def handle_cast({:new_conf, conf}, state) do
    case Keyword.get(conf, :interval) do
      nil ->
        {:noreply, state}

      new_interval ->
        {:noreply, Map.put(state, :interval, new_interval)}
    end
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
