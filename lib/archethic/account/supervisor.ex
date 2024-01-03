defmodule Archethic.Account.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.Account.GenesisSupervisor
  alias Archethic.Account.MemTables.GenesisInputLedger
  alias Archethic.Account.MemTables.TokenLedger
  alias Archethic.Account.MemTables.UCOLedger
  alias Archethic.Account.MemTables.StateLedger
  alias Archethic.Account.MemTablesLoader

  alias Archethic.Utils

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: Archethic.AccountSupervisor)
  end

  def init(_args) do
    children = [
      TokenLedger,
      UCOLedger,
      StateLedger,
      GenesisInputLedger,
      GenesisSupervisor,
      MemTablesLoader
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :one_for_one)
  end
end
