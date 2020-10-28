defmodule Uniris.SelfRepair do
  @moduledoc """
  Synchronization for all the Uniris nodes relies on the self-repair mechanism started during
  the bootstrapping phase and stores last synchronization date after each cycle.
  """

  alias __MODULE__.Scheduler
  alias __MODULE__.Sync

  @doc """
  Start the self repair synchronization scheduler
  """
  @spec start_scheduler(network_patch :: binary()) :: :ok
  defdelegate start_scheduler(patch), to: Scheduler

  @doc """
  Start the synchronization process using the last synchronization date
  """
  @spec sync(network_patch :: binary()) :: :ok
  def sync(patch) when is_binary(patch) do
    date = Sync.last_sync_date()
    Sync.load_missed_transactions(date, patch)
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
end
