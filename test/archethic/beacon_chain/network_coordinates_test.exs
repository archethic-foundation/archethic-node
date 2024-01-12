defmodule Archethic.BeaconChain.NetworkCoordinatesTest do
  use ArchethicCase

  alias Archethic.BeaconChain.NetworkCoordinates

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetNetworkStats
  alias Archethic.P2P.Message.NetworkStats
  alias Archethic.P2P.Node

  doctest NetworkCoordinates
  @timeout 1_000

  import Mox

  describe "fetch_network_stats/1" do
    setup do
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
    end

    test "should retrieve the stats for a given summary time" do
      MockClient
      |> expect(:send_message, 3, fn
        _, %GetNetworkStats{}, _ ->
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

      assert [
               [0, 0, 0, 100, 100, 90],
               [0, 0, 0, 110, 105, 105],
               [0, 0, 0, 90, 90, 90],
               [100, 110, 90, 0, 0, 0],
               [100, 105, 90, 0, 0, 0],
               [90, 105, 90, 0, 0, 0]
             ] ==
               NetworkCoordinates.fetch_network_stats(DateTime.utc_now(), @timeout)
               |> Nx.to_list()
    end

    test "should filter stats that are different from expected nodes for a subset" do
      ok_stats_1 = %NetworkStats{
        stats: %{
          <<0>> => %{
            <<0::8, 0::8, 1::8, "key_b0">> => [%{latency: 100}, %{latency: 100}, %{latency: 100}],
            <<0::8, 0::8, 1::8, "key_b1">> => [%{latency: 100}, %{latency: 100}, %{latency: 100}],
            <<0::8, 0::8, 1::8, "key_b2">> => [%{latency: 100}, %{latency: 100}, %{latency: 100}]
          }
        }
      }

      ok_stats_2 = %NetworkStats{
        stats: %{
          <<0>> => %{
            <<0::8, 0::8, 1::8, "key_b0">> => [%{latency: 200}, %{latency: 200}, %{latency: 200}],
            <<0::8, 0::8, 1::8, "key_b1">> => [%{latency: 200}, %{latency: 200}, %{latency: 200}],
            <<0::8, 0::8, 1::8, "key_b2">> => [%{latency: 200}, %{latency: 200}, %{latency: 200}]
          }
        }
      }

      wrong_stats = %NetworkStats{
        stats: %{
          <<0>> => %{
            <<0::8, 0::8, 1::8, "key_b0">> => [%{latency: 100}, %{latency: 200}],
            <<0::8, 0::8, 1::8, "key_b1">> => [%{latency: 100}, %{latency: 105}, %{latency: 90}],
            <<0::8, 0::8, 1::8, "key_b2">> => [%{latency: 90}, %{latency: 105}, %{latency: 90}]
          }
        }
      }

      wrong_node = P2P.get_node_info!(<<0::8, 0::8, 1::8, "key_b0">>)
      ok_node_1 = P2P.get_node_info!(<<0::8, 0::8, 1::8, "key_b1">>)
      ok_node_2 = P2P.get_node_info!(<<0::8, 0::8, 1::8, "key_b2">>)

      MockClient
      |> expect(:send_message, 3, fn
        ^wrong_node, %GetNetworkStats{}, _ ->
          {:ok, wrong_stats}

        ^ok_node_1, %GetNetworkStats{}, _ ->
          {:ok, ok_stats_1}

        ^ok_node_2, %GetNetworkStats{}, _ ->
          {:ok, ok_stats_2}
      end)

      assert [
               [0, 0, 0, 150, 150, 150],
               [0, 0, 0, 150, 150, 150],
               [0, 0, 0, 150, 150, 150],
               [150, 150, 150, 0, 0, 0],
               [150, 150, 150, 0, 0, 0],
               [150, 150, 150, 0, 0, 0]
             ] ==
               NetworkCoordinates.fetch_network_stats(DateTime.utc_now(), @timeout)
               |> Nx.to_list()
    end
  end
end
