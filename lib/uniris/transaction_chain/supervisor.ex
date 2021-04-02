defmodule Uniris.TransactionChain.Supervisor do
  @moduledoc false

  use Supervisor

  alias Uniris.TransactionChain.MemTables.KOLedger
  alias Uniris.TransactionChain.MemTables.PendingLedger
  alias Uniris.TransactionChain.MemTablesLoader

  alias Uniris.Utils

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: Uniris.TransactionChainSupervisor)
  end

  def init(_args) do
    optional_children = [PendingLedger, KOLedger, MemTablesLoader]

    children = Utils.configurable_children(optional_children)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
