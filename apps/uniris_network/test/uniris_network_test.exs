defmodule UnirisNetworkTest do
  use ExUnit.Case

  alias UnirisNetwork.Node
  alias UnirisNetwork.NodeSupervisor
  alias UnirisCrypto, as: Crypto

  test "list_nodes/0 should retrieve the supervised nodes processes" do
    {:ok, pub} = Crypto.generate_random_keypair()
    {:ok, pub2} = Crypto.generate_random_keypair()
    DynamicSupervisor.start_child(NodeSupervisor, {
      Node,
      first_public_key: pub, last_public_key: pub, ip: "88.100.200.10", port: 3000
    })

    DynamicSupervisor.start_child(NodeSupervisor, {
          Node,
          first_public_key: pub2, last_public_key: pub2, ip: "77.22.19.202", port: 3000
                                  })

    nodes = UnirisNetwork.list_nodes()
    assert length(nodes) == 2
    assert List.first(nodes).first_public_key == pub
    assert Enum.at(nodes, 1).first_public_key == pub2
  end
end
