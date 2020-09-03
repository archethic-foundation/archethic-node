defmodule Uniris.SelfRepair do
  @moduledoc """
  Process responsible of the self repair mechanism by pulling for each interval
  the last unsynchronized beacon chain slots.

  It downloads the missing transactions and node updates
  """
  use GenServer

  alias __MODULE__.SlotFinder
  alias __MODULE__.SlotSync

  alias Uniris.Utils

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start the self repair synchronization

  If fire_sync? is true, the self repair sync will be executed right away.
  Otherwise we need to wait the next cycle of repair to synchronize new transactions.
  """
  @spec start_sync(node_patch :: binary(), fire_sync? :: boolean()) :: :ok
  def start_sync(node_patch, fire_sync? \\ true)
      when is_binary(node_patch) and is_boolean(fire_sync?) do
    GenServer.call(__MODULE__, {:start_sync, node_patch, fire_sync?})
  end

  @doc """
  Return the last synchronization date from the previous cycle of self repair
  """
  @spec last_sync_date() :: DateTime.t()
  def last_sync_date do
    file = last_sync_file()

    if File.exists?(file) do
      file
      |> File.read!()
      |> String.to_integer()
      |> DateTime.from_unix!()
      |> Utils.truncate_datetime()
    else
      Application.get_env(:uniris, Uniris.SelfRepair)[:network_startup_date]
    end
  end

  def init(opts) do
    interval = Keyword.get(opts, :interval)

    {:ok,
     %{
       interval: interval,
       last_sync_date: last_sync_date()
     }}
  end

  def handle_call(
        {:start_sync, node_patch, fire_sync?},
        {from_pid, _ref},
        state = %{interval: interval}
      ) do
    if fire_sync? do
      {:reply, :ok, Map.put(state, :node_patch, node_patch), {:continue, {:first_sync, from_pid}}}
    else
      schedule_sync(Utils.time_offset(interval))

      new_state =
        state
        |> Map.put(:node_patch, node_patch)
        |> Map.put(:last_sync_date, update_last_sync_date())

      {:reply, :ok, new_state}
    end
  end

  def handle_continue(
        {:first_sync, from_pid},
        state = %{
          node_patch: node_patch,
          last_sync_date: last_sync_date,
          interval: interval
        }
      ) do
    synchronize(last_sync_date, node_patch)
    send(from_pid, :sync_finished)
    schedule_sync(Utils.time_offset(interval))
    {:noreply, Map.put(state, :last_sync_date, update_last_sync_date())}
  end

  def handle_info(
        :sync,
        state = %{
          interval: interval,
          last_sync_date: last_sync_date,
          node_patch: node_patch
        }
      ) do
    Logger.info("Self-repair synchronization started from #{inspect(last_sync_date)}")
    synchronize(last_sync_date, node_patch)
    schedule_sync(Utils.time_offset(interval))
    {:noreply, Map.put(state, :last_sync_date, update_last_sync_date())}
  end

  defp update_last_sync_date do
    next_sync_date = Utils.truncate_datetime(DateTime.utc_now())
    store_last_sync_date(next_sync_date)
    next_sync_date
  end

  defp schedule_sync(interval) when is_integer(interval) and interval >= 0 do
    Process.send_after(self(), :sync, interval * 1000)
  end

  # Retreive missing transactions from the missing beacon chain slots
  # Beacon chain pools are retrieved from the given latest synchronization
  # date including all the beacon subsets (i.e <<0>>, <<1>>, etc.)
  # Once retrieved, the transactions are downloaded and stored if not exists locally
  defp synchronize(last_sync_date, node_patch) do
    last_sync_date
    |> SlotFinder.missing_slots(node_patch)
    |> SlotSync.handle_missing_slots(node_patch)
  end

  defp store_last_sync_date(date) do
    data = DateTime.to_unix(date) |> Integer.to_string()
    filename = last_sync_file()
    File.mkdir_p!(Path.dirname(filename))
    File.write!(filename, data, [:write])
  end

  defp last_sync_file do
    relative_filepath =
      :uniris
      |> Application.get_env(__MODULE__)
      |> Keyword.get(:last_sync_file, "priv/p2p/last_sync")

    Application.app_dir(:uniris, relative_filepath)
  end
end
