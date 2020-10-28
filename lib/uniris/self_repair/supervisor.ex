defmodule Uniris.SelfRepair.Supervisor do
  @moduledoc false

  use Supervisor

  alias Uniris.SelfRepair.Scheduler
  alias Uniris.SelfRepair.Sync

  alias Uniris.Utils

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    init_last_sync_file()

    children = [
      {Scheduler, Application.get_env(:uniris, Scheduler)}
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :one_for_one)
  end

  defp init_last_sync_file do
    sync_config = Application.get_env(:uniris, Sync)
    last_sync_file = Keyword.fetch!(sync_config, :last_sync_file)
    startup_date = Keyword.fetch!(sync_config, :network_startup_date)

    unless File.exists?(last_sync_file) do
      Sync.store_last_sync_date(startup_date)
    end
  end
end
