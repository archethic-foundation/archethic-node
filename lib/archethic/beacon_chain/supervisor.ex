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

  @spec init(any) :: {:ok, {Supervisor.sup_flags(), list(Supervisor.child_spec())}}
  def init(_args) do
    children =
      [
        {SlotTimer, [], []},
        {SummaryTimer, [], []},
        {SubsetSupervisor, [], []},
        {Update, [], []}
      ]
      |> Utils.configurable_children()

    Supervisor.init(children, strategy: :one_for_one)
  end
end
