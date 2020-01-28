defmodule UnirisNetwork.NodeTest do
  use ExUnit.Case

  alias UnirisNetwork.Node
  alias UnirisCrypto, as: Crypto

  test "start_link/1 should create a new node" do
    {:ok, pub} = Crypto.generate_random_keypair()
    {:ok, pub2} = Crypto.generate_random_keypair()
    {:ok, pid} = Node.start_link(first_public_key: pub, last_public_key: pub2, ip: "127.0.0.1", port: 3000)
    assert Process.alive?(pid)
    assert match?([{_, _}], Registry.lookup(UnirisNetwork.NodeRegistry, pub))
    assert match?([{_, _}], Registry.lookup(UnirisNetwork.NodeRegistry, pub2))
  end

  test "available/1 should state the node as available" do
    {:ok, pub} = Crypto.generate_random_keypair()
    {:ok, pid} = Node.start_link(first_public_key: pub, last_public_key: pub, ip: "127.0.0.1", port: 3000)
    Node.available(pub)
    assert match? %{availability: 1}, :sys.get_state(pid)
  end

  test "unavailable/1 should state the node as unavailable" do
    {:ok, pub} = Crypto.generate_random_keypair()
    {:ok, pid} = Node.start_link(first_public_key: pub, last_public_key: pub, ip: "127.0.0.1", port: 3000)
    Node.available(pub)
    Node.unavailable(pub)
    assert match? %{availability: 0}, :sys.get_state(pid)
  end

  test "details/1 should retrieve the node information" do
    
    {:ok, pub} = Crypto.generate_random_keypair()
    {:ok, pub2} = Crypto.generate_random_keypair()
    {:ok, pid} = Node.start_link(first_public_key: pub, last_public_key: pub2, ip: "127.0.0.1", port: 3000)

    assert match?(%Node{}, Node.details(pub))
    assert match?(%Node{}, Node.details(pub2))
  end

  test "update_basics/4 should update the basic node information" do
    {:ok, pub} = Crypto.generate_random_keypair()
    {:ok, _pid} = Node.start_link(first_public_key: pub, last_public_key: pub, ip: "127.0.0.1", port: 3000)
    {:ok, pub2} = Crypto.generate_random_keypair()
    Node.update_basics(pub, pub2, "88.100.242.12", 3000)
    node = Node.details(pub)
    assert node.last_public_key == pub2
    assert node.ip == "88.100.242.12"
  end

  test "update_network_patch/2 should update the network patch" do
    {:ok, pub} = Crypto.generate_random_keypair()
    {:ok, _pid} = Node.start_link(first_public_key: pub, last_public_key: pub, ip: "127.0.0.1", port: 3000)
    Node.update_network_patch(pub, "AA0")
    %{network_patch: network_patch} = Node.details(pub)
    assert network_patch == "AA0"
  end

  test "should restore from saved state after a crash" do
    {:ok, pub} = Crypto.generate_random_keypair()#

    {:ok, pid} = Node.start_link(first_public_key: pub, last_public_key: pub, ip: "127.0.0.1", port: 3000)
    Node.available(pub)

    Process.flag(:trap_exit, true)

    Process.exit(pid, :shutdown)
    Process.sleep(100)

    Node.start_link(first_public_key: pub, last_public_key: pub, ip: "127.0.0.1", port: 3000)
    assert match?(%{availability: 1}, Node.details(pub))
  end
end
