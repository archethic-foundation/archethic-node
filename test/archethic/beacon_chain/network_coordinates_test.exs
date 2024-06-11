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

  @tag :simulation
  test "simulate network coordinates on 2D plan" do
    csv_stats_06_06_2024 = """
    0,70,161,111,152,120,72,124,113,157,67,0,0,93,118,132,0,143,102,0,0,0,102,157,146
    70,0,149,74,147,83,42,87,82,130,41,0,0,51,75,108,0,167,64,0,0,0,61,212,161
    161,149,0,147,73,151,156,142,150,100,159,0,0,138,147,81,0,70,129,0,0,0,134,110,127
    111,74,147,0,115,110,87,119,113,156,70,0,0,103,111,138,0,145,109,0,0,0,104,143,150
    152,147,73,115,0,134,138,148,139,115,161,0,0,146,146,99,0,99,151,0,0,0,141,137,126
    120,83,151,110,134,0,87,130,117,156,79,0,0,110,119,137,0,150,111,0,0,0,117,145,150
    72,42,156,87,138,87,0,86,81,162,30,0,0,56,85,141,0,48,47,0,0,0,64,197,160
    124,87,142,119,148,130,86,0,119,149,76,0,0,104,124,141,0,144,108,0,0,0,111,152,153
    113,82,150,113,139,117,81,119,0,151,75,0,0,102,116,126,0,156,107,0,0,0,106,150,155
    157,130,100,156,115,156,162,149,151,0,147,0,0,113,149,136,0,155,119,0,0,0,108,174,162
    67,41,159,70,161,79,30,76,75,147,0,0,0,58,79,54,0,46,46,0,0,0,60,207,175
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    93,51,138,103,146,110,56,104,102,113,58,0,0,0,93,138,0,168,46,0,0,0,58,198,177
    118,75,147,111,146,119,85,124,116,149,79,0,0,93,0,138,0,156,101,0,0,0,101,166,146
    132,108,81,138,99,137,141,141,126,136,54,0,0,138,138,0,0,87,125,0,0,0,122,66,189
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    143,167,70,145,99,150,48,144,156,155,46,0,0,168,156,87,0,0,180,0,0,0,175,39,176
    102,64,129,109,151,111,47,108,107,119,46,0,0,46,101,125,0,180,0,0,0,0,45,195,180
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    102,61,134,104,141,117,64,111,106,108,60,0,0,58,101,122,0,175,45,0,0,0,0,188,169
    157,212,110,143,137,145,197,152,150,174,207,0,0,198,166,66,0,39,195,0,0,0,188,0,92
    146,161,127,150,126,150,160,153,155,162,175,0,0,177,146,189,0,176,180,0,0,0,169,92,0
    """

    nodes_names = [
      "Rhone Alpes (BEYS)",
      "Rhone-Alpes",
      "Toronto",
      "Rhone Alpes (BEYS)",
      "Neywork",
      "Rhone Alpes (BEYS)",
      "PACA",
      "Rhone Alpes (BEYS)",
      "Rhone Alpes (BEYS)",
      "Sydney",
      "PACA",
      "Nouvelle-Aquitaine",
      "Île-de-France",
      "Frankfurt",
      "Rhone Alpes (BEYS)",
      "Singapore",
      "Occitanie",
      "Bangalore",
      "Amsterdam",
      "Île-de-France",
      "Occitanie",
      "Nouvelle-Aquitaine",
      "london",
      "Canada",
      "Sanfrancisco"
    ]

    matrix =
      csv_stats_06_06_2024
      |> NimbleCSV.RFC4180.parse_string(skip_headers: false)
      |> Enum.map(fn row ->
        Enum.map(row, &String.to_integer/1)
      end)
      |> Nx.tensor()

    coordinates = matrix |> NetworkCoordinates.get_matrix_coordinates() |> Nx.to_list()

    gnuplot_coordinates =
      coordinates
      |> Enum.with_index()
      |> Enum.map(fn {[x, y], index} ->
        [
          x,
          y,
          Enum.at(nodes_names, index)
        ]
      end)

    Gnuplot.plot(
      [
        # [:plot, "-", :with, :points, :using, '1:2']
        [:plot, "-", :using, '1:2:3', :with, :labels, :offset, '1,-1']
      ],
      [gnuplot_coordinates]
    )
  end
end
