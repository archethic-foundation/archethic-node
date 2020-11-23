defmodule Uniris.BeaconChain.GenICMPTest do
  use ExUnit.Case

  alias Uniris.BeaconChain.GenICMP

  doctest GenICMP

  test "ping/1 should ping the destination node" do
    assert {:ok, %{data: <<222, 173, 190, 239>>, id: 0, seq: 0}} = GenICMP.ping({127, 0, 0, 1})
  end
end
