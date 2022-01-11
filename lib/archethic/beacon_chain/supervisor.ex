defmodule ArchEthic.BeaconChain.Supervisor do
  @moduledoc false

  use Supervisor

  alias ArchEthic.BeaconChain.SlotTimer
  alias ArchEthic.BeaconChain.SummaryTimer
  alias ArchEthic.BeaconChain.SubsetSupervisor

  alias ArchEthic.Utils

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    schedulers =
      Utils.configurable_children([
        {SlotTimer, Application.get_env(:archethic, SlotTimer), []},
        {SummaryTimer, Application.get_env(:archethic, SummaryTimer), []}
      ])

    children = schedulers ++ [SubsetSupervisor]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
