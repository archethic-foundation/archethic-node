defmodule ArchEthic.BeaconChain.Subset.P2PSamplingTest do
  use ArchEthicCase

  alias ArchEthic.BeaconChain.Subset.P2PSampling

  alias ArchEthic.P2P
  alias ArchEthic.P2P.ConnectionRegistry
  alias ArchEthic.P2P.Message.Ok
  alias ArchEthic.P2P.Message.Ping
  alias ArchEthic.P2P.Node

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

  test "get_p2p_views/1 fetch p2p node availability and latency for the given list of nodes" do
    nodes = [
      %Node{ip: {127, 0, 0, 1}, port: 3001, first_public_key: "key1"},
      %Node{ip: {127, 0, 0, 1}, port: 3002, first_public_key: "key2"},
      %Node{ip: {127, 0, 0, 1}, port: 3003, first_public_key: "key3"},
      %Node{ip: {127, 0, 0, 1}, port: 3004, first_public_key: "key4"}
    ]

    MockClient
    |> stub(:new_connection, fn _, _, _, key ->
      Registry.register(ConnectionRegistry, {:bearer_conn, key}, [])
      {:ok, self()}
    end)
    |> expect(:send_message, fn %Node{port: 3001}, %Ping{} ->
      {:ok, %Ok{}}
    end)
    |> expect(:send_message, fn %Node{port: 3002}, %Ping{} ->
      Process.sleep(100)
      {:ok, %Ok{}}
    end)
    |> expect(:send_message, fn %Node{port: 3003}, %Ping{} ->
      Process.sleep(300)
      {:ok, %Ok{}}
    end)
    |> expect(:send_message, fn %Node{port: 3004}, %Ping{} ->
      {:error, :network_issue}
    end)

    Enum.each(nodes, &P2P.add_and_connect_node/1)

    assert [{true, 0}, {true, node2_lat}, {true, node3_lat}, {false, 0}] =
             P2PSampling.get_p2p_views(nodes)

    assert node2_lat < node3_lat
  end
end
