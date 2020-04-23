defmodule UnirisCore.P2PTest do
  use ExUnit.Case, async: false
  doctest UnirisCore.P2P

  alias UnirisCore.P2P
  alias UnirisCore.P2P.NodeSupervisor
  alias UnirisCore.P2P.Node

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    MockNodeClient
    |> stub(:start_link, fn opts ->
      pid = Keyword.get(opts, :parent_pid)
      send(pid, :connected)

      client_pid =
        spawn(fn ->
          receive do
            msg ->
              msg
          end
        end)

      {:ok, client_pid}
    end)
    |> stub(:send_message, fn _, msg -> msg end)

    on_exit(fn ->
      clean_supervisor()
    end)

    :ok
  end

  defp clean_supervisor do
    DynamicSupervisor.which_children(NodeSupervisor)
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(NodeSupervisor, pid)
    end)
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

    Node.authorize("key")
    Node.set_ready("key2")

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
