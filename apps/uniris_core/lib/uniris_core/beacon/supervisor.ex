defmodule UnirisCore.BeaconSupervisor do
  @moduledoc false

  use Supervisor

  alias UnirisCore.Utils

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: UnirisBeaconSupervisor)
  end

  def init(_opts) do
    subsets = Enum.map(0..254, &:binary.encode_unsigned(&1))

    slot_interval = Application.get_env(:uniris_core, UnirisCore.BeaconSlotTimer)[:slot_interval]

    children =
      [
        {Registry, keys: :unique, name: UnirisCore.BeaconSubsetRegistry},
        {UnirisCore.BeaconSubsets, subsets}
      ] ++
        Utils.configurable_children(
          [{UnirisCore.BeaconSlotTimer, [slot_interval: slot_interval], []}] ++
            Enum.map(subsets, &{UnirisCore.BeaconSubset, [subset: &1], [id: &1]})
        )

    Supervisor.init(children, strategy: :one_for_one)
  end
end
