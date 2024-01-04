defmodule Archethic.UTXO.DBLedger.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.Utils

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    db_impl = Application.get_env(:archethic, Archethic.UTXO.DBLedger)
    db_opts = Application.get_env(:archethic, db_impl, [])

    optional_children = [{db_impl, db_opts}]
    children = Utils.configurable_children(optional_children)

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
