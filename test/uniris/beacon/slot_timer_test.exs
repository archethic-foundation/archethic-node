defmodule Uniris.BeaconSlotTimerTest do
  use ExUnit.Case

  alias Uniris.BeaconSlotTimer
  alias Uniris.BeaconSubsetRegistry
  alias Uniris.BeaconSubsets

  setup do
    Enum.each(BeaconSubsets.all(), fn subset ->
      Registry.register(BeaconSubsetRegistry, subset, [])
    end)

    start_supervised!({BeaconSlotTimer, interval: "* * * * * *", trigger_offset: 1})
    :ok
  end

  @tag time_based: true
  test "receive create_slot message after timer elapsed" do
    receive do
      {:create_slot, time} ->
        assert time.second == 59
    end
  end
end
