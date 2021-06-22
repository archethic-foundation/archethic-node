defmodule ArchEthic.Account.Supervisor do
  @moduledoc false

  use Supervisor

  alias ArchEthic.Account.MemTables.NFTLedger
  alias ArchEthic.Account.MemTables.UCOLedger
  alias ArchEthic.Account.MemTablesLoader

  alias ArchEthic.Utils

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: ArchEthic.AccountSupervisor)
  end

  def init(_args) do
    children = [
      NFTLedger,
      UCOLedger,
      MemTablesLoader
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :one_for_one)
  end
end
