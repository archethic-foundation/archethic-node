defmodule Archethic.P2P.Message.GetNetworkStatsTest do
  @moduledoc false
  use ExUnit.Case

  alias Archethic.P2P.Message.GetNetworkStats
  doctest GetNetworkStats

  describe "serialize/deserialize" do
    summary_time = DateTime.utc_now() |> DateTime.truncate(:second)

    msg = %GetNetworkStats{summary_time: summary_time}

    assert {^msg, <<>>} =
             msg
             |> GetNetworkStats.serialize()
             |> GetNetworkStats.deserialize()
  end
end
