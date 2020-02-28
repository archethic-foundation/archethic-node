defmodule UnirisNetwork.DefaultImplTest do
  use ExUnit.Case

  alias UnirisNetwork.Node
  alias UnirisNetwork.NodeSupervisor
  alias UnirisNetwork.ConnectionSupervisor
  alias UnirisCrypto, as: Crypto
  alias UnirisNetwork.DefaultImpl, as: Network

  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    MockP2P
    |> stub(:start_link, fn _, _, _, pid ->
      send(pid, :connected)
      {:ok, self()}
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
    pub = Crypto.generate_random_keypair()
    pub2 = Crypto.generate_random_keypair()

    {:ok, _} = DynamicSupervisor.start_child(NodeSupervisor, {
      Node,
      first_public_key: pub, last_public_key: pub, ip: {88, 100, 200, 10}, port: 3000
    })

    {:ok, _} =
      DynamicSupervisor.start_child(NodeSupervisor, {
        Node,
        first_public_key: pub2, last_public_key: pub2, ip: {77, 22, 19, 202}, port: 3000
      })

    nodes = Network.list_nodes()
    assert Enum.map(nodes, & &1.last_public_key) == [pub, pub2]
  end

  test "add_node/1 should spawn a Node information process and a SupervisedConnection process" do
    node = %Node{
      first_public_key: Crypto.generate_random_keypair(),
      last_public_key: Crypto.generate_random_keypair(),
      ip: {88, 100, 200, 10},
      port: 3000
    }

    Network.add_node(node)
    Process.sleep(200)

    node_processes = DynamicSupervisor.which_children(NodeSupervisor)
    connection_processes = DynamicSupervisor.which_children(ConnectionSupervisor)

    assert length(node_processes) == 1
    assert length(connection_processes) == 1

    [{pid, _}] = Registry.lookup(UnirisNetwork.NodeRegistry, node.first_public_key)
    assert true = Process.alive?(pid)
    %{first_public_key: node_first_public_key} = :sys.get_state(pid)
    assert node_first_public_key == node.first_public_key

    [{pid, _}] = Registry.lookup(UnirisNetwork.ConnectionRegistry, node.first_public_key)
    assert true = Process.alive?(pid)

    {_, %{public_key: node_public_key}} = :sys.get_state(pid)
    assert node_public_key == node.first_public_key
  end

  test "node_info/1 should give node details" do
    node = %Node{
      first_public_key: Crypto.generate_random_keypair(),
      last_public_key: Crypto.generate_random_keypair(),
      ip: {88, 100, 200, 10},
      port: 3000
    }

    :ok = Network.add_node(node)
    Process.sleep(100)

    %Node{
      last_public_key: last_pub,
      first_public_key: first_pub,
      ip: ip,
      port: port
    } = Network.node_info(node.first_public_key)

    assert last_pub == node.last_public_key
    assert first_pub == node.first_public_key
    assert ip == node.ip
    assert port == node.port

    assert %Node{} = Network.node_info({88, 100, 200, 10})
  end
end
