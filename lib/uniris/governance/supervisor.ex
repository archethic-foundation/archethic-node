defmodule Uniris.Governance.Supervisor do
  @moduledoc false

  use Supervisor

  alias Uniris.Governance.Code.CICD
  alias Uniris.Governance.Pools.MemTable
  alias Uniris.Governance.Pools.MemTableLoader

  alias Uniris.Utils

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg)
  end

  def init(_args) do
    children = [
      Utils.impl(CICD),
      MemTable,
      MemTableLoader
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :rest_for_one)
  end
end
