defmodule Archethic.OracleChain.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.OracleChain.MemTable
  alias Archethic.OracleChain.MemTableLoader
  alias Archethic.OracleChain.Scheduler

  alias Archethic.Utils
  alias Archethic.Utils.HydratingCache.CachesManager

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args)
  end

  def init(_args) do
    scheduler_conf = Application.get_env(:archethic, Scheduler)

    children = [
      CachesManager,
      MemTable,
      MemTableLoader,
      {Scheduler, scheduler_conf}
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :one_for_one)
  end
end
