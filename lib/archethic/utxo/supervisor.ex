defmodule Archethic.UTXO.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.UTXO.DBLedger.Supervisor, as: DBLedgerSupervisor
  alias Archethic.UTXO.Loader
  alias Archethic.UTXO.LoaderSupervisor
  alias Archethic.UTXO.MemoryLedger

  alias Archethic.Utils

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: Archethic.UTXOSupervisor)
  end

  def init(_) do
    children = [
      DBLedgerSupervisor,
      MemoryLedger,
      {PartitionSupervisor, child_spec: Loader, name: LoaderSupervisor, partitions: 20}
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :one_for_one)
  end
end
