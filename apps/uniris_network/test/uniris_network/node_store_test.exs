defmodule UnirisNetwork.NodeStoreTest do
  use ExUnit.Case

  alias UnirisNetwork.Node
  alias UnirisNetwork.NodeStore


  setup do
    :ets.delete_all_objects(:node_store_list)
    :ets.delete_all_objects(:node_store_last)
    :ok
  end

  test "list_nodes/0 should return the list of nodes" do
    assert [] == NodeStore.list_nodes()

    node = %Node{
      ip: "127.0.0.1",
      port: 3000,
      availability: 1,
      average_availability: 1,
      geo_patch: "AA0",
      first_public_key: "",
      last_public_key: "mypublickey"
    }

    :ets.insert(:node_store_list, {"mypublickey", node})

    assert [node] == NodeStore.list_nodes()
  end

  test "fetch_node/1 should return an error when the node doesn't exist in the table" do
    {:ok, pub} = UnirisCrypto.generate_random_keypair()
    assert {:error, :node_not_exists} = NodeStore.fetch_node(pub)
  end

  test "put_node/1 should create a node in  the list of nodes when it does not exist" do

    node = %Node{
      ip: "127.0.0.1",
      port: 3000,
      availability: 1,
      average_availability: 1,
      geo_patch: "AA0",
      first_public_key: "mypublickey",
      last_public_key: "mypublickey"
    }

    :ok = NodeStore.put_node(node)
    assert [%Node{last_public_key: "mypublickey"}] = NodeStore.list_nodes()
  end

  test "put_node/1 should update the node in the table when its exists" do

    {:ok, pub} = UnirisCrypto.generate_random_keypair()

    node = %Node{
      ip: "127.0.0.1",
      port: 3000,
      availability: 1,
      average_availability: 1,
      geo_patch: "AA0",
      first_public_key: pub,
      last_public_key: pub
    }

    NodeStore.put_node(node)

    {:ok, next_pub} = UnirisCrypto.generate_random_keypair()
    node = Map.put(node, :last_public_key, next_pub)

    :ok = NodeStore.put_node(node)
    assert %Node{} = NodeStore.fetch_node(pub)
    assert %Node{} = NodeStore.fetch_node(next_pub)
  end
end
