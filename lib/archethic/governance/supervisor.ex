defmodule ArchEthic.Governance.Supervisor do
  @moduledoc false

  use Supervisor

  alias ArchEthic.Governance.Code.CICD
  alias ArchEthic.Governance.Pools.MemTable
  alias ArchEthic.Governance.Pools.MemTableLoader

  alias ArchEthic.Utils

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
