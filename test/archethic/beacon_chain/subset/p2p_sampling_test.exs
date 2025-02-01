defmodule Archethic.BeaconChain.Subset.P2PSamplingTest do
  use ArchethicCase

  alias Archethic.BeaconChain.Subset.P2PSampling

  alias Archethic.P2P
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Ping
  alias Archethic.P2P.Node

  @moduletag capture_log: true

  import Mox

  test "list_nodes_to_sample/1 filter available nodes based on the subset given" do
    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3003,
      first_public_key: <<0::8, 0::8, 7::8, :crypto.strong_rand_bytes(31)::binary>>,
      available?: true
    })

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3004,
      first_public_key: <<0::8, 0::8, 1::8, :crypto.strong_rand_bytes(31)::binary>>,
      available?: true
    })

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3005,
      first_public_key: <<0::8, 0::8, 2::8, :crypto.strong_rand_bytes(31)::binary>>,
      available?: true
    })

    assert [%Node{port: 3004}] = P2PSampling.list_nodes_to_sample(<<1>>)
  end

  test "get_p2p_views/2 fetch p2p node availability time and latency for the given subset" do
    node1 = %Node{ip: {127, 0, 0, 1}, port: 3001, first_public_key: "key1"}
    node2 = %Node{ip: {127, 0, 0, 1}, port: 3002, first_public_key: "key2"}
    node3 = %Node{ip: {127, 0, 0, 1}, port: 3003, first_public_key: "key3"}
    node4 = %Node{ip: {127, 0, 0, 1}, port: 3004, first_public_key: "key4"}

    nodes = [node1, node2, node3, node4]

    MockClient
    |> expect(:send_message, fn ^node1, %Ping{}, _ ->
      Process.sleep(10)
      {:ok, %Ok{}}
    end)
    |> expect(:send_message, fn ^node2, %Ping{}, _ ->
      Process.sleep(100)
      {:ok, %Ok{}}
    end)
    |> expect(:send_message, fn ^node3, %Ping{}, _ ->
      Process.sleep(300)
      {:ok, %Ok{}}
    end)
    |> expect(:send_message, fn ^node4, %Ping{}, _ ->
      {:error, :network_issue}
    end)
    |> expect(:get_availability_timer, fn "key4", _ -> 0 end)
    |> expect(:get_availability_timer, fn "key1", _ -> 600 end)
    |> expect(:get_availability_timer, fn "key2", _ -> 500 end)
    |> expect(:get_availability_timer, fn "key3", _ -> 365 end)

    Enum.each(nodes, &P2P.add_and_connect_node/1)

    assert [{600, node1_lat}, {500, node2_lat}, {365, node3_lat}, {0, 0}] =
             P2PSampling.get_p2p_views(nodes)

    assert node1_lat < node2_lat
    assert node2_lat < node3_lat
  end
end
