defmodule Uniris.Account.Supervisor do
  @moduledoc false

  use Supervisor

  alias Uniris.Account.MemTables.UCOLedger
  alias Uniris.Account.MemTablesLoader

  alias Uniris.Utils

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: Uniris.AccountSupervisor)
  end

  def init(_args) do
    children = [
      UCOLedger,
      MemTablesLoader
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :one_for_one)
  end
end
