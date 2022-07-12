defmodule Archethic.BeaconChain.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.BeaconChain.SlotTimer
  alias Archethic.BeaconChain.SummaryTimer
  alias Archethic.BeaconChain.SubsetSupervisor
  alias Archethic.BeaconChain.Update

  alias Archethic.Utils

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    schedulers =
      Utils.configurable_children([
        {SlotTimer, Application.get_env(:archethic, SlotTimer), []},
        {SummaryTimer, Application.get_env(:archethic, SummaryTimer), []}
      ])

    children = schedulers ++ [SubsetSupervisor, Update]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
