defmodule ArchEthic.TransactionChain.Supervisor do
  @moduledoc false

  use Supervisor

  alias ArchEthic.TransactionChain.MemTables.KOLedger
  alias ArchEthic.TransactionChain.MemTables.PendingLedger
  alias ArchEthic.TransactionChain.MemTablesLoader

  alias ArchEthic.Utils

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: ArchEthic.TransactionChainSupervisor)
  end

  def init(_args) do
    optional_children = [PendingLedger, KOLedger, MemTablesLoader]

    children = Utils.configurable_children(optional_children)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
