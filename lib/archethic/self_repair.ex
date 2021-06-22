defmodule ArchEthic.SelfRepair do
  @moduledoc """
  Synchronization for all the ArchEthic nodes relies on the self-repair mechanism started during
  the bootstrapping phase and stores last synchronization date after each cycle.
  """

  alias __MODULE__.Scheduler
  alias __MODULE__.Sync

  @doc """
  Start the self repair synchronization scheduler
  """
  @spec start_scheduler(DateTime.t()) :: :ok
  defdelegate start_scheduler(last_sync_date), to: Scheduler

  @doc """
  Start the bootstrap's synchronization process using the last synchronization date
  """
  @spec bootstrap_sync(last_sync_date :: DateTime.t(), network_patch :: binary()) :: :ok
  def bootstrap_sync(date = %DateTime{}, patch) when is_binary(patch) do
    Sync.load_missed_transactions(date, patch, true)
    put_last_sync_date(DateTime.utc_now())
  end

  @doc """
  Return the last synchronization date from the previous cycle of self repair
  """
  @spec last_sync_date() :: DateTime.t()
  defdelegate last_sync_date, to: Sync

  @doc """
  Return the default last sync date
  """
  @spec default_last_sync_date() :: DateTime.t()
  defdelegate default_last_sync_date, to: Sync

  @doc """
  Set the next last synchronization date
  """
  @spec put_last_sync_date(DateTime.t()) :: :ok
  defdelegate put_last_sync_date(datetime), to: Sync, as: :store_last_sync_date

  def config_change(changed_conf) do
    changed_conf
    |> Keyword.get(Scheduler)
    |> Scheduler.config_change()
  end
end
