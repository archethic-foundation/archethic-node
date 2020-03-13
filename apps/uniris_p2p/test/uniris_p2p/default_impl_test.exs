defmodule UnirisP2P.DefaultImplTest do
  use ExUnit.Case

  alias UnirisP2P.Node
  alias UnirisP2P.NodeSupervisor
  alias UnirisP2P.ConnectionSupervisor
  alias UnirisP2P.NodeRegistry
  alias UnirisP2P.ConnectionRegistry
  alias UnirisP2P.DefaultImpl, as: P2P

  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    MockClient
    |> stub(:connect, fn _, _ ->
      {:ok, ""}
    end)

    DynamicSupervisor.which_children(NodeSupervisor)
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(NodeSupervisor, pid)
    end)

    DynamicSupervisor.which_children(ConnectionSupervisor)
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(ConnectionSupervisor, pid)
    end)

    :ok
  end

  test "list_nodes/0 should retrieve the supervised nodes processes" do
    pub = :crypto.strong_rand_bytes(64)
    pub2 = :crypto.strong_rand_bytes(64)

    {:ok, _} =
      DynamicSupervisor.start_child(NodeSupervisor, {
        Node,
        first_public_key: pub, last_public_key: pub, ip: {88, 100, 200, 10}, port: 3000
      })

    {:ok, _} =
      DynamicSupervisor.start_child(NodeSupervisor, {
        Node,
        first_public_key: pub2, last_public_key: pub2, ip: {77, 22, 19, 202}, port: 3000
      })

    nodes = P2P.list_nodes()
    assert Enum.map(nodes, & &1.last_public_key) == [pub, pub2]
  end

  test "add_node/1 should spawn a Node information process" do
    node = %Node{
      first_public_key: :crypto.strong_rand_bytes(64),
      last_public_key: :crypto.strong_rand_bytes(64),
      ip: {88, 100, 200, 10},
      port: 3000
    }

    P2P.add_node(node)

    node_processes = DynamicSupervisor.which_children(NodeSupervisor)

    assert length(node_processes) == 1

    [{pid, _}] = Registry.lookup(NodeRegistry, node.first_public_key)
    assert true = Process.alive?(pid)
    %{first_public_key: node_first_public_key} = :sys.get_state(pid)
    assert node_first_public_key == node.first_public_key
  end

  test "connect_node/1 should spawn a new supervied connection process" do
    node = %Node{
      first_public_key: :crypto.strong_rand_bytes(64),
      last_public_key: :crypto.strong_rand_bytes(64),
      ip: {88, 100, 200, 10},
      port: 3000
    }

    P2P.connect_node(node)
    connection_processes = DynamicSupervisor.which_children(ConnectionSupervisor)
    assert length(connection_processes) == 1

    [{pid, _}] = Registry.lookup(ConnectionRegistry, node.first_public_key)
    assert true = Process.alive?(pid)

    {_, %{public_key: node_public_key}} = :sys.get_state(pid)
    assert node_public_key == node.first_public_key
  end

  test "node_info/1 should give node details" do
    node = %Node{
      first_public_key: :crypto.strong_rand_bytes(64),
      last_public_key: :crypto.strong_rand_bytes(64),
      ip: {88, 100, 200, 10},
      port: 3000
    }

    :ok = P2P.add_node(node)
    Process.sleep(100)

    {:ok,
     %Node{
       last_public_key: last_pub,
       first_public_key: first_pub,
       ip: ip,
       port: port
     }} = P2P.node_info(node.first_public_key)

    assert last_pub == node.last_public_key
    assert first_pub == node.first_public_key
    assert ip == node.ip
    assert port == node.port

    assert {:ok, %Node{}} = P2P.node_info({88, 100, 200, 10})
  end
end
