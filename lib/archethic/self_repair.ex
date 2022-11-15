defmodule Archethic.SelfRepair do
  @moduledoc """
  Synchronization for all the Archethic nodes relies on the self-repair mechanism started during
  the bootstrapping phase and stores last synchronization date after each cycle.
  """

  alias __MODULE__.Scheduler
  alias __MODULE__.Sync

  alias Archethic.BeaconChain

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.Scheduler, as: CronScheduler

  require Logger

  @doc """
  Start the self repair synchronization scheduler
  """
  @spec start_scheduler() :: :ok
  defdelegate start_scheduler, to: Scheduler

  @doc """
  Start the bootstrap's synchronization process using the last synchronization date
  """
  @spec bootstrap_sync(last_sync_date :: DateTime.t()) :: :ok
  def bootstrap_sync(date = %DateTime{}) do
    # Loading transactions can take a lot of time to be achieve and can overpass an epoch.
    # So to avoid missing a beacon summary epoch, we save the starting date and update the last sync date with it
    # at the end of loading (in case there is a crash during self repair).

    # Summary time after the the last synchronization date
    summary_time = BeaconChain.next_summary_date(date)

    # Before the first summary date, synchronization is useless
    # as no data have been aggregated
    if DateTime.diff(DateTime.utc_now(), summary_time) >= 0 do
      start_date = DateTime.utc_now()
      :ok = Sync.load_missed_transactions(date)
      put_last_sync_date(start_date)

      # At the end of self repair, if a new beacon summary as been created
      # we run bootstrap_sync again until the last beacon summary is loaded
      case DateTime.utc_now()
           |> BeaconChain.previous_summary_time()
           |> DateTime.compare(start_date) do
        :gt ->
          bootstrap_sync(start_date)

        _ ->
          :ok
      end
    else
      Logger.info("Synchronization skipped (before first summary date)")
    end
  end

  @doc """
  Return the last synchronization date from the previous cycle of self repair
  """
  @spec last_sync_date() :: DateTime.t() | nil
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
