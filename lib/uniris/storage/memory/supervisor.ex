defmodule Uniris.Storage.MemorySupervisor do
  @moduledoc false

  use Supervisor

  alias Uniris.Storage.Memory.ChainLookup
  alias Uniris.Storage.Memory.KOLedger
  alias Uniris.Storage.Memory.NetworkLedger
  alias Uniris.Storage.Memory.PendingLedger
  alias Uniris.Storage.Memory.UCOLedger

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    children = [
      ChainLookup,
      NetworkLedger,
      PendingLedger,
      UCOLedger,
      KOLedger
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
