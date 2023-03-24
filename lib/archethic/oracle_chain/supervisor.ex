defmodule Archethic.OracleChain.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.OracleChain.MemTable
  alias Archethic.OracleChain.MemTableLoader
  alias Archethic.OracleChain.Scheduler
  alias Archethic.OracleChain.ServiceCacheSupervisor

  alias Archethic.Utils

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args)
  end

  def init(_args) do
    scheduler_conf = Application.get_env(:archethic, Scheduler)

    children = [
      MemTable,
      MemTableLoader,
      {Scheduler, scheduler_conf},
      ServiceCacheSupervisor
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :one_for_one)
  end
end
