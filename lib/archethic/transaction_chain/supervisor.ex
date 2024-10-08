defmodule Archethic.TransactionChain.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.TransactionChain.DBLedger.Supervisor, as: DBLedgerSupervisor
  alias Archethic.TransactionChain.MemTables.KOLedger
  alias Archethic.TransactionChain.MemTables.PendingLedger
  # alias Archethic.TransactionChain.MemTablesLoader

  alias Archethic.Utils

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: Archethic.TransactionChainSupervisor)
  end

  def init(_args) do
    optional_children = [
      PendingLedger,
      KOLedger,
      # MemTablesLoader,
      DBLedgerSupervisor
    ]

    children = Utils.configurable_children(optional_children)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
