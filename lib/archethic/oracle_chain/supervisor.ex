defmodule ArchEthic.OracleChain.Supervisor do
  @moduledoc false

  use Supervisor

  alias ArchEthic.OracleChain.MemTable
  alias ArchEthic.OracleChain.MemTableLoader
  alias ArchEthic.OracleChain.Scheduler

  alias ArchEthic.Utils

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args)
  end

  def init(_args) do
    scheduler_conf = Application.get_env(:archethic, ArchEthic.OracleChain.Scheduler)

    children = [
      MemTable,
      MemTableLoader,
      {Scheduler, scheduler_conf}
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :one_for_one)
  end
end
