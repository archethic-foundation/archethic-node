defmodule Uniris.BeaconSupervisor do
  @moduledoc false

  use Supervisor

  alias Uniris.BeaconSlotTimer
  alias Uniris.BeaconSubset
  alias Uniris.BeaconSubsetRegistry
  alias Uniris.BeaconSubsets
  alias Uniris.Utils

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    subsets = Enum.map(0..255, &:binary.encode_unsigned(&1))

    interval = Application.get_env(:uniris, BeaconSlotTimer)[:interval]
    trigger_offset = Application.get_env(:uniris, BeaconSlotTimer)[:trigger_offset]

    children =
      [
        {Registry, keys: :unique, name: BeaconSubsetRegistry},
        {BeaconSubsets, subsets}
      ] ++
        Utils.configurable_children(
          [{BeaconSlotTimer, [interval: interval, trigger_offset: trigger_offset], []}] ++
            Enum.map(subsets, &{BeaconSubset, [subset: &1], [id: &1]})
        )

    Supervisor.init(children, strategy: :one_for_one)
  end
end
