defmodule Archethic.UTXO.DBLedger.FileImpl.Supervisor do
  @moduledoc false

  use Supervisor

  require Logger

  def start_link(arg \\ []) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    Archethic.UTXO.DBLedger.FileImpl.setup_folder!()
    children = []

    Supervisor.init(children, strategy: :one_for_one)
  end
end
