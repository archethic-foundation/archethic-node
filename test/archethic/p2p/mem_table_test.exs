defmodule Archethic.P2P.MemTableTest do
  use ExUnit.Case

  alias Archethic.P2P.MemTable
  alias Archethic.P2P.Node

  describe "add_node/1" do
    test "should insert a node in the P2P table" do
      MemTable.start_link()

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: "key1",
        last_public_key: "key2",
        geo_patch: "AFZ",
        network_patch: "AAA",
        average_availability: 0.9,
        available?: true,
        synced?: true,
        authorized?: true,
        authorization_date: ~U[2020-10-22 23:19:45.797109Z],
        enrollment_date: ~U[2020-10-22 23:19:45.797109Z],
        last_update_date: ~U[2020-10-22 23:19:45.797109Z],
        availability_update: ~U[2020-10-22 23:19:45.797109Z],
        transport: :tcp,
        reward_address:
          <<0, 163, 237, 233, 93, 14, 241, 241, 8, 144, 218, 105, 16, 138, 243, 223, 17, 182, 87,
            9, 7, 53, 146, 174, 125, 5, 244, 42, 35, 209, 142, 24, 164>>,
        last_address:
          <<0, 165, 32, 187, 102, 112, 133, 38, 17, 232, 54, 228, 173, 254, 94, 179, 32, 173, 88,
            122, 234, 88, 139, 82, 26, 113, 42, 8, 183, 190, 163, 221, 112>>,
        origin_public_key:
          <<0, 0, 172, 147, 188, 9, 66, 252, 112, 77, 143, 178, 233, 51, 125, 102, 244, 36, 232,
            185, 38, 7, 238, 128, 41, 30, 192, 61, 223, 119, 62, 249, 39, 212>>
      }

      :ok = MemTable.add_node(node)

      {
        :ets.tab2list(:archethic_node_discovery),
        :ets.tab2list(:archethic_authorized_nodes),
        :ets.tab2list(:archethic_node_keys)
      }

      assert [
               {
                 "key1",
                 "key2",
                 {127, 0, 0, 1},
                 3000,
                 4000,
                 "AFZ",
                 "AAA",
                 0.9,
                 ~U[2020-10-22 23:19:45.797109Z],
                 :tcp,
                 <<0, 163, 237, 233, 93, 14, 241, 241, 8, 144, 218, 105, 16, 138, 243, 223, 17,
                   182, 87, 9, 7, 53, 146, 174, 125, 5, 244, 42, 35, 209, 142, 24, 164>>,
                 <<0, 165, 32, 187, 102, 112, 133, 38, 17, 232, 54, 228, 173, 254, 94, 179, 32,
                   173, 88, 122, 234, 88, 139, 82, 26, 113, 42, 8, 183, 190, 163, 221, 112>>,
                 <<0, 0, 172, 147, 188, 9, 66, 252, 112, 77, 143, 178, 233, 51, 125, 102, 244, 36,
                   232, 185, 38, 7, 238, 128, 41, 30, 192, 61, 223, 119, 62, 249, 39, 212>>,
                 true,
                 ~U[2020-10-22 23:19:45.797109Z],
                 true,
                 ~U[2020-10-22 23:19:45.797109Z],
                 nil
               }
             ] = :ets.tab2list(:archethic_node_discovery)

      assert [{"key1", ~U[2020-10-22 23:19:45.797109Z]}] =
               :ets.tab2list(:archethic_authorized_nodes)

      assert([{"key2", "key1"}] = :ets.tab2list(:archethic_node_keys))
    end

    test "should update a node entry" do
      MemTable.start_link()

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: "key1",
        last_public_key: "key2",
        geo_patch: "AFZ",
        network_patch: "AAA",
        average_availability: 0.9,
        available?: true,
        synced?: true,
        authorized?: true,
        authorization_date: ~U[2020-10-22 23:19:45.797109Z],
        enrollment_date: ~U[2020-10-22 23:19:45.797109Z],
        last_update_date: ~U[2020-10-22 23:19:45.797109Z],
        availability_update: ~U[2020-10-22 23:19:45.797109Z],
        transport: :tcp,
        reward_address:
          <<0, 163, 237, 233, 93, 14, 241, 241, 8, 144, 218, 105, 16, 138, 243, 223, 17, 182, 87,
            9, 7, 53, 146, 174, 125, 5, 244, 42, 35, 209, 142, 24, 164>>,
        last_address:
          <<0, 165, 32, 187, 102, 112, 133, 38, 17, 232, 54, 228, 173, 254, 94, 179, 32, 173, 88,
            122, 234, 88, 139, 82, 26, 113, 42, 8, 183, 190, 163, 221, 112>>,
        origin_public_key:
          <<0, 0, 172, 147, 188, 9, 66, 252, 112, 77, 143, 178, 233, 51, 125, 102, 244, 36, 232,
            185, 38, 7, 238, 128, 41, 30, 192, 61, 223, 119, 62, 249, 39, 212>>
      }

      :ok = MemTable.add_node(node)

      :ok =
        MemTable.add_node(%{
          node
          | ip: {80, 20, 10, 122},
            port: 5000,
            last_public_key: "key5",
            synced?: false,
            last_update_date: ~U[2020-10-22 23:20:45.797109Z],
            availability_update: ~U[2020-10-23 23:20:45.797109Z],
            available?: false,
            transport: :sctp,
            mining_public_key:
              <<3, 0, 224, 186, 136, 105, 213, 175, 202, 16, 163, 252, 116, 117, 68, 105, 114, 78,
                141, 48, 56, 211, 235, 26, 97, 145, 234, 76, 202, 52, 251, 52, 161, 200>>
        })

      assert [
               {
                 "key1",
                 "key5",
                 {80, 20, 10, 122},
                 5000,
                 4000,
                 "AFZ",
                 "AAA",
                 0.9,
                 ~U[2020-10-22 23:19:45.797109Z],
                 :sctp,
                 <<0, 163, 237, 233, 93, 14, 241, 241, 8, 144, 218, 105, 16, 138, 243, 223, 17,
                   182, 87, 9, 7, 53, 146, 174, 125, 5, 244, 42, 35, 209, 142, 24, 164>>,
                 <<0, 165, 32, 187, 102, 112, 133, 38, 17, 232, 54, 228, 173, 254, 94, 179, 32,
                   173, 88, 122, 234, 88, 139, 82, 26, 113, 42, 8, 183, 190, 163, 221, 112>>,
                 <<0, 0, 172, 147, 188, 9, 66, 252, 112, 77, 143, 178, 233, 51, 125, 102, 244, 36,
                   232, 185, 38, 7, 238, 128, 41, 30, 192, 61, 223, 119, 62, 249, 39, 212>>,
                 false,
                 ~U[2020-10-22 23:20:45.797109Z],
                 false,
                 ~U[2020-10-23 23:20:45.797109Z],
                 <<3, 0, 224, 186, 136, 105, 213, 175, 202, 16, 163, 252, 116, 117, 68, 105, 114,
                   78, 141, 48, 56, 211, 235, 26, 97, 145, 234, 76, 202, 52, 251, 52, 161, 200>>
               }
             ] = :ets.lookup(:archethic_node_discovery, "key1")
    end
  end

  describe "get_node/1" do
    test "should retrieve node by the first public key" do
      MemTable.start_link()

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: "key1",
        last_public_key: "key2"
      }

      :ok = MemTable.add_node(node)
      assert {:ok, node} == MemTable.get_node("key1")
    end

    test "should retrieve node by the last public key" do
      MemTable.start_link()

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: "key1",
        last_public_key: "key2"
      }

      :ok = MemTable.add_node(node)
      assert {:ok, node} == MemTable.get_node("key2")
    end

    test "should return an error if the node is not found" do
      MemTable.start_link()
      assert {:error, :not_found} = MemTable.get_node("key10")
    end
  end

  test "list_nodes/0 should list all the nodes in the table" do
    MemTable.start_link()

    node = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      http_port: 4000,
      first_public_key: "key1",
      last_public_key: "key2"
    }

    MemTable.add_node(node)
    assert [node] == MemTable.list_nodes()
  end

  test "authorized_nodes/0 should list only the authorized nodes" do
    MemTable.start_link()

    node1 = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      http_port: 4000,
      first_public_key: "key1",
      last_public_key: "key2"
    }

    MemTable.add_node(node1)

    node2 = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      http_port: 4000,
      first_public_key: "key3",
      last_public_key: "key3",
      authorized?: true,
      available?: true,
      authorization_date: ~U[2020-10-22 23:19:45.797109Z]
    }

    MemTable.add_node(node2)
    assert [node2] == MemTable.authorized_nodes()
  end

  test "available_nodes/0 shoud list only the nodes which are globally available" do
    MemTable.start_link()

    node1 = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      http_port: 4000,
      first_public_key: "key1",
      last_public_key: "key2"
    }

    MemTable.add_node(node1)

    node2 = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      http_port: 4000,
      first_public_key: "key3",
      last_public_key: "key3",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    }

    MemTable.add_node(node2)
    assert [node2] == MemTable.available_nodes()
  end

  test "list_node_first_public_keys/0 should list all the node first public keys" do
    MemTable.start_link()

    node1 = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      http_port: 4000,
      first_public_key: "key1",
      last_public_key: "key2"
    }

    MemTable.add_node(node1)

    node2 = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      http_port: 4000,
      first_public_key: "key3",
      last_public_key: "key3"
    }

    MemTable.add_node(node2)
    assert ["key1", "key3"] = MemTable.list_node_first_public_keys()
  end

  test "list_authorized_public_keys/0 should list all the public keys of the authorized nodes" do
    MemTable.start_link()

    node1 = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      http_port: 4000,
      first_public_key: "key1",
      last_public_key: "key2"
    }

    MemTable.add_node(node1)

    node2 = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      http_port: 4000,
      first_public_key: "key3",
      last_public_key: "key3",
      authorized?: true,
      authorization_date: ~U[2020-10-22 23:19:45.797109Z]
    }

    MemTable.add_node(node2)
    assert ["key3"] = MemTable.list_authorized_public_keys()
  end

  test "authorize_node/2 should define a node as authorized" do
    MemTable.start_link()

    :ok =
      MemTable.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: "key1",
        last_public_key: "key1"
      })

    :ok = MemTable.authorize_node("key1", ~U[2020-10-22 23:45:41.181903Z])
    assert ["key1"] = MemTable.list_authorized_public_keys()
  end

  test "unauthorize_node/1 should unset a node as authorized" do
    MemTable.start_link()

    :ok =
      MemTable.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: "key1",
        last_public_key: "key1",
        authorized?: true,
        authorization_date: ~U[2020-10-22 23:45:41.181903Z]
      })

    assert ["key1"] = MemTable.list_authorized_public_keys()

    :ok = MemTable.unauthorize_node("key1")
    assert [] = MemTable.list_authorized_public_keys()
  end

  describe "get_first_node_key/1" do
    test "should retrieve first node key from the first key" do
      MemTable.start_link()

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: "key1",
        last_public_key: "key2"
      }

      MemTable.add_node(node)
      assert "key1" = MemTable.get_first_node_key("key1")
    end

    test "should retrieve first node key from the last key" do
      MemTable.start_link()

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: "key1",
        last_public_key: "key2"
      }

      MemTable.add_node(node)
      assert "key1" = MemTable.get_first_node_key("key2")
    end
  end

  test "set_node_available/2 should define a node as available" do
    MemTable.start_link()

    node = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      http_port: 4000,
      first_public_key: "key1",
      last_public_key: "key2"
    }

    MemTable.add_node(node)
    :ok = MemTable.set_node_available("key1", ~U[2020-10-22 23:45:41Z])

    {:ok, %Node{available?: true, availability_update: ~U[2020-10-22 23:45:41Z]}} =
      MemTable.get_node("key1")

    MemTable.add_node(node)
    :ok = MemTable.set_node_available("key1", ~U[2020-10-23 23:45:41Z])

    assert {:ok, %Node{available?: true, availability_update: ~U[2020-10-23 23:45:41Z]}} =
             MemTable.get_node("key1")
  end

  test "set_node_unavailable/2 should define a node as unavailable" do
    MemTable.start_link()

    node = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      http_port: 4000,
      first_public_key: "key1",
      last_public_key: "key2"
    }

    MemTable.add_node(node)
    :ok = MemTable.set_node_available("key1", ~U[2020-10-22 23:45:41Z])
    :ok = MemTable.set_node_unavailable("key1", ~U[2020-10-23 23:45:41Z])

    assert {:ok, %Node{available?: false, availability_update: ~U[2020-10-23 23:45:41Z]}} =
             MemTable.get_node("key1")
  end

  test "set_node_synced/1 should define a node as synchronized" do
    MemTable.start_link()

    node = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      http_port: 4000,
      first_public_key: "key1",
      last_public_key: "key2"
    }

    MemTable.add_node(node)
    :ok = MemTable.set_node_synced("key1")
    assert {:ok, %Node{synced?: true}} = MemTable.get_node("key1")
  end

  test "set_node_unsynced/1 should define a node as unsynchronized" do
    MemTable.start_link()

    node = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      http_port: 4000,
      first_public_key: "key1",
      last_public_key: "key2"
    }

    MemTable.add_node(node)
    :ok = MemTable.set_node_synced("key1")
    :ok = MemTable.set_node_unsynced("key1")
    assert {:ok, %Node{synced?: false}} = MemTable.get_node("key1")
  end

  test "update_node_average_availability/2 should update node average availability" do
    MemTable.start_link()

    node = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      http_port: 4000,
      first_public_key: "key1",
      last_public_key: "key2",
      average_availability: 0.4
    }

    MemTable.add_node(node)
    :ok = MemTable.update_node_average_availability("key1", 0.8)
    assert {:ok, %Node{average_availability: 0.8}} = MemTable.get_node("key1")
  end

  test "update_node_network_patch/2 should update node network patch" do
    MemTable.start_link()

    node = %Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      http_port: 4000,
      first_public_key: "key1",
      last_public_key: "key2",
      network_patch: "AAA"
    }

    MemTable.add_node(node)
    :ok = MemTable.update_node_network_patch("key1", "3FC")
    assert {:ok, %Node{network_patch: "3FC"}} = MemTable.get_node("key1")
  end
end
