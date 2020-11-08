defmodule Uniris.BeaconChain.GenICMPTest do

    use ExUnit.Case

    alias Uniris.BeaconChain.GenICMP

    test "ping" do
        assert {:error, :eacces} = GenICMP.ping({127, 0, 0, 1})
    end
end