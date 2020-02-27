defmodule UnirisNetwork.DefaultImplTest do
  use ExUnit.Case

  alias UnirisNetwork.Node
  alias UnirisNetwork.NodeSupervisor
  alias UnirisCrypto, as: Crypto

  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    MockP2P
    |> stub(:start_link, fn _, _, _, pid ->
      send(pid, :connected)
      {:ok, self()}
      
    end)
    :ok 
  end

  test "list_nodes/0 should retrieve the supervised nodes processes" do
    pub = Crypto.generate_random_keypair()
    pub2 = Crypto.generate_random_keypair()
    DynamicSupervisor.start_child(NodeSupervisor, {
      Node,
      first_public_key: pub, last_public_key: pub, ip: "88.100.200.10", port: 3000
    })

    {:ok, pid} = DynamicSupervisor.start_child(NodeSupervisor, {
          Node,
          first_public_key: pub2, last_public_key: pub2, ip: "77.22.19.202", port: 3000
                                  })

    nodes = UnirisNetwork.list_nodes()
    Enum.any?(nodes, &(&1.last_public_key == pub))
  end

  test "add_node/1 should spawn a new process under the supervision tree" do
    node = %Node{
      first_public_key: Crypto.generate_random_keypair(),
      last_public_key: Crypto.generate_random_keypair(),
      ip: "88.100.200.10",
      port: 3000,
      geo_patch: "AAA",
      availability: 1,
      average_availability: 1
    }

    UnirisNetwork.add_node(node)
    Process.sleep(200)
    [{pid, _}] = Registry.lookup(UnirisNetwork.NodeRegistry, node.first_public_key)
    assert true = Process.alive?(pid)
    %{first_public_key: node_first_public_key} = :sys.get_state(pid)
    assert node_first_public_key == node.first_public_key
  end

  test "node_info/1 should given node details" do
    node = %Node{
      first_public_key: Crypto.generate_random_keypair(),
      last_public_key: Crypto.generate_random_keypair(),
      ip: "88.100.200.10",
      port: 3000,
      geo_patch: "AAA",
      availability: 1,
      average_availability: 1
    }

    :ok = UnirisNetwork.add_node(node)
    Process.sleep(100)
    node_details = UnirisNetwork.node_info(node.first_public_key)
    assert node_details == node
  end
end
