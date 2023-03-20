defmodule Archethic.BeaconChain.NetworkCoordinatesTest do
  use ArchethicCase

  alias Archethic.BeaconChain.NetworkCoordinates

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetNetworkStats
  alias Archethic.P2P.Message.NetworkStats
  alias Archethic.P2P.Node

  doctest NetworkCoordinates

  import Mox

  describe "fetch_network_stats/1" do
    test "should retrieve the stats for a given summary time" do
      beacon_nodes =
        Enum.map(0..2, fn i ->
          %Node{
            first_public_key: <<0::8, 0::8, 1::8, "key_b#{i}">>,
            last_public_key: <<0::8, 0::8, 1::8, "key_b#{i}">>,
            ip: {127, 0, 0, 1},
            port: 3000 + i,
            authorized?: true,
            authorization_date: DateTime.utc_now(),
            available?: true,
            geo_patch: "BBB"
          }
        end)

      sampled_nodes =
        Enum.map(0..2, fn i ->
          %Node{
            first_public_key: <<0::8, 0::8, 0::8, "key_s#{i}">>,
            last_public_key: <<0::8, 0::8, 0::8, "key_s#{i}">>,
            ip: {127, 0, 0, 10 + i},
            port: 3010 + i
          }
        end)

      Enum.each(beacon_nodes, &P2P.add_and_connect_node/1)
      Enum.each(sampled_nodes, &P2P.add_and_connect_node/1)

      MockClient
      |> stub(:send_message, fn
        _, %GetNetworkStats{subsets: _}, _ ->
          {:ok,
           %NetworkStats{
             stats: %{
               <<0>> => %{
                 <<0::8, 0::8, 1::8, "key_b0">> => [
                   %{latency: 100},
                   %{latency: 110},
                   %{latency: 90}
                 ],
                 <<0::8, 0::8, 1::8, "key_b1">> => [
                   %{latency: 100},
                   %{latency: 105},
                   %{latency: 90}
                 ],
                 <<0::8, 0::8, 1::8, "key_b2">> => [
                   %{latency: 90},
                   %{latency: 105},
                   %{latency: 90}
                 ]
               }
             }
           }}
      end)

      assert Nx.tensor([
               [0, 0, 0, 100, 100, 90],
               [0, 0, 0, 110, 105, 105],
               [0, 0, 0, 90, 90, 90],
               [100, 110, 90, 0, 0, 0],
               [100, 105, 90, 0, 0, 0],
               [90, 105, 90, 0, 0, 0]
             ]) == NetworkCoordinates.fetch_network_stats(DateTime.utc_now())
    end
  end
end
