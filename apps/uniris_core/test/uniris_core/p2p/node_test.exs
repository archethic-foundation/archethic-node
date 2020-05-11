defmodule UnirisCore.P2P.NodeTest do
  use ExUnit.Case

  alias UnirisCore.P2P.Node
  alias UnirisCore.P2P.NodeRegistry

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    stub(MockNodeClient, :send_message, fn _, _, msg -> msg end)
    :ok
  end

  describe "start_link/1" do
    test "should spawn a process with node information registered by its keys and IP" do
      {:ok, pid} =
        Node.start_link(
          %Node{
            ip: {127, 0, 0, 1},
            port: 3000,
            last_public_key: "last_public_key",
            first_public_key: "first_public_key"
          }
        )

      assert %Node{
               ip: {127, 0, 0, 1},
               port: 3000,
               last_public_key: "last_public_key",
               first_public_key: "first_public_key"
             } = :sys.get_state(pid)

      assert [{_pid, _}] = Registry.lookup(NodeRegistry, {127, 0, 0, 1})
      assert [{_pid, _}] = Registry.lookup(NodeRegistry, "first_public_key")
      assert [{_pid, _}] = Registry.lookup(NodeRegistry, "last_public_key")
    end
  end

  describe "node_details/1" do
    test "should get node information based on the public key" do
      Node.start_link(
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          last_public_key: "last_public_key",
          first_public_key: "first_public_key"
        }
      )

      assert %Node{
               ip: {127, 0, 0, 1},
               port: 3000,
               last_public_key: "last_public_key",
               first_public_key: "first_public_key"
             } = Node.details("first_public_key")
    end

    test "should get node information based on the ip address" do
      Node.start_link(
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          last_public_key: "last_public_key",
          first_public_key: "first_public_key"
        }
      )

      assert %Node{
               ip: {127, 0, 0, 1},
               port: 3000,
               last_public_key: "last_public_key",
               first_public_key: "first_public_key"
             } = Node.details({127, 0, 0, 1})
    end
  end

  test "update_basics/4 should update the last public key, ip, port, and performed a new GeoIP lookup" do
    Node.start_link(
      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "last_public_key",
        first_public_key: "first_public_key"
      }
    )

    Node.update_basics("first_public_key", "new_public_key", {88, 100, 50, 30}, 3005)

    assert %Node{
             ip: {88, 100, 50, 30},
             port: 3005
           } = Node.details("first_public_key")
  end

  test "update_network_patch/2 should update the network patch" do
    Node.start_link(
      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "last_public_key",
        first_public_key: "first_public_key"
      }
    )

    Node.update_network_patch("first_public_key", "AAC")

    assert %Node{
             network_patch: "AAC"
           } = Node.details("first_public_key")
  end

  test "update_average_availability/2 should change the average availability and reset the history" do
    Node.start_link(
      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "last_public_key",
        first_public_key: "first_public_key"
      }
    )

    Node.update_average_availability("first_public_key", 0.8)

    assert %Node{average_availability: 0.8, availability_history: <<>>} =
             Node.details("first_public_key")
  end

  test "authorize/1 should mark the node as authorized validator node" do
    Node.start_link(
      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "last_public_key",
        first_public_key: "first_public_key"
      }
    )

    Node.authorize("first_public_key")
    assert %Node{authorized?: true} = Node.details("first_public_key")
  end

  test "set_ready/1 should mark the node as ready" do
    Node.start_link(
      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "last_public_key",
        first_public_key: "first_public_key"
      }
    )

    Node.set_ready("first_public_key")
    assert %Node{ready?: true} = Node.details("first_public_key")
  end

  test "send_message/2 should send message to the client and get response" do
    Node.start_link(
      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "last_public_key",
        first_public_key: "first_public_key"
      }
    )

    assert :hello = Node.send_message("last_public_key", :hello)
  end

  test "set_enrollment_date/2 should set the enrollment date to the node" do
    {:ok, pid} =
      Node.start_link(
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          last_public_key: "last_public_key",
          first_public_key: "first_public_key"
        }
      )

    now = DateTime.utc_now()
    :ok = Node.set_enrollment_date("first_public_key", now)
    %Node{enrollment_date: date} = :sys.get_state(pid)
    assert date == now
  end

  test "available/1 should mark the available" do
    Node.start_link(
      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "last_public_key",
        first_public_key: "first_public_key",
        available?: false
      }
    )

    :ok = Node.available("first_public_key")
    %Node{available?: true} = Node.details("first_public_key")
  end

  test "unavailable/1 should mark the node as unavailable" do
    Node.start_link(
      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: "last_public_key",
        first_public_key: "first_public_key"
      }
    )

    :ok = Node.unavailable("first_public_key")
    %Node{available?: false} = Node.details("first_public_key")
  end
end
