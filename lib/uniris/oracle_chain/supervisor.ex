defmodule Uniris.OracleChain.Supervisor do
  @moduledoc false

  use Supervisor

  alias Uniris.OracleChain.MemTable
  alias Uniris.OracleChain.MemTableLoader
  alias Uniris.OracleChain.Scheduler

  alias Uniris.Utils

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args)
  end

  def init(_args) do
    scheduler_conf = Application.get_env(:uniris, Uniris.OracleChain.Scheduler)

    children = [
      MemTable,
      MemTableLoader,
      {Scheduler, scheduler_conf}
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :one_for_one)
  end
end
