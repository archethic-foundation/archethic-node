defmodule UnirisCore.BeaconSlotTimerTest do
  use ExUnit.Case

  alias UnirisCore.BeaconSlotTimer
  alias UnirisCore.BeaconSubsetRegistry
  alias UnirisCore.BeaconSubsets

  setup do
    Enum.each(BeaconSubsets.all(), fn subset ->
      Registry.register(BeaconSubsetRegistry, subset, [])
    end)

    start_supervised!({BeaconSlotTimer, slot_interval: 500})
    {:ok, %{interval: 500}}
  end

  test "after the slot interval receive the create_slot message", %{interval: interval} do
    Process.sleep(interval)

    assert_receive {:create_slot, _time}
  end
end
