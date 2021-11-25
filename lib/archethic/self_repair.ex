defmodule ArchEthic.SelfRepair do
  @moduledoc """
  Synchronization for all the ArchEthic nodes relies on the self-repair mechanism started during
  the bootstrapping phase and stores last synchronization date after each cycle.
  """

  alias __MODULE__.Scheduler
  alias __MODULE__.Sync

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.Scheduler, as: CronScheduler

  @doc """
  Start the self repair synchronization scheduler
  """
  @spec start_scheduler() :: :ok
  defdelegate start_scheduler, to: Scheduler

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
  Set the next last synchronization date
  """
  @spec put_last_sync_date(DateTime.t()) :: :ok
  defdelegate put_last_sync_date(datetime), to: Sync, as: :store_last_sync_date

  def config_change(changed_conf) do
    changed_conf
    |> Keyword.get(Scheduler)
    |> Scheduler.config_change()
  end

  @doc """
  Return the previous scheduler time from a given date
  """
  @spec get_previous_scheduler_repair_time(DateTime.t()) :: DateTime.t()
  def get_previous_scheduler_repair_time(date_from = %DateTime{}) do
    Scheduler.get_interval()
    |> CronParser.parse!(true)
    |> CronScheduler.get_previous_run_date!(DateTime.to_naive(date_from))
    |> DateTime.from_naive!("Etc/UTC")
  end
end
