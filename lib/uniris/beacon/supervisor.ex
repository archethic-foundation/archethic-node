defmodule Uniris.BeaconSupervisor do
  @moduledoc false

  use Supervisor

  alias Uniris.Beacon
  alias Uniris.BeaconSlotTimer
  alias Uniris.BeaconSubset
  alias Uniris.BeaconSubsetRegistry
  alias Uniris.Utils

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    Beacon.init_subsets()

    interval = Application.get_env(:uniris, BeaconSlotTimer)[:interval]
    trigger_offset = Application.get_env(:uniris, BeaconSlotTimer)[:trigger_offset]

    subsets = Beacon.list_subsets()

    children =
      [
        {Registry, keys: :unique, name: BeaconSubsetRegistry}
      ] ++
        Utils.configurable_children(
          [{BeaconSlotTimer, [interval: interval, trigger_offset: trigger_offset], []}] ++
            Enum.map(subsets, &{BeaconSubset, [subset: &1], [id: &1]})
        )

    Supervisor.init(children, strategy: :one_for_one)
  end
end
