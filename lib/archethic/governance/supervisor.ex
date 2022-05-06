defmodule Archethic.Governance.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.Governance.Code.CICD
  alias Archethic.Governance.Pools.MemTable
  alias Archethic.Governance.Pools.MemTableLoader

  alias Archethic.Utils

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg)
  end

  def init(_args) do
    children = [
      CICD,
      MemTable,
      MemTableLoader
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :rest_for_one)
  end
end
