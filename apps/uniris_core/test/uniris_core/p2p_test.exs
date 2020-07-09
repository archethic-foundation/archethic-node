defmodule UnirisCore.P2PTest do
  use UnirisCoreCase, async: false
  doctest UnirisCore.P2P

  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node
  alias UnirisCore.P2P.NodeSupervisor

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    stub(MockNodeClient, :send_message, fn _, _, msg -> msg end)
    :ok
  end

  test "add_node/1 should add the node in the supervision tree" do
    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "key",
      last_public_key: "key"
    })

    node_processes = DynamicSupervisor.which_children(NodeSupervisor)
    assert length(node_processes) == 1
  end

  test "list_nodes/0 should return the list of nodes" do
    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "key",
      last_public_key: "key"
    })

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "key2",
      last_public_key: "key2"
    })

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "key3",
      last_public_key: "key3"
    })

    Node.authorize("key", DateTime.utc_now())
    Node.set_ready("key2", DateTime.utc_now())

    assert length(P2P.list_nodes()) == 3
  end

  test "node_info/1 should return retrieve node information or return error when not found" do
    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "key",
      last_public_key: "key"
    })

    Process.sleep(100)

    assert {:ok, %Node{ip: {127, 0, 0, 1}}} = P2P.node_info("key")
    assert {:error, :not_found} = P2P.node_info("key2")
  end
end
