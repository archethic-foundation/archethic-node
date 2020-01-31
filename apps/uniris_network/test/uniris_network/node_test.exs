defmodule UnirisNetwork.NodeTest do
  use ExUnit.Case

  alias UnirisNetwork.Node
  alias UnirisCrypto, as: Crypto

  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    MockSupervisedConnection
    |> stub(:start_link, fn _, _, _ ->
      {:ok,
       spawn_link(fn ->
         receive do
           _ ->
             :ok
         end
       end)}
    end)

    :ok
  end

  test "start_link/1 should create a new node, register it and create a connection " do
    {:ok, pub} = Crypto.generate_random_keypair()
    {:ok, pub2} = Crypto.generate_random_keypair()

    {:ok, pid} =
      Node.start_link(first_public_key: pub, last_public_key: pub2, ip: "127.0.0.1", port: 3000)

    assert Process.alive?(pid)
    assert match?([{_, _}], Registry.lookup(UnirisNetwork.NodeRegistry, pub))
    assert match?([{_, _}], Registry.lookup(UnirisNetwork.NodeRegistry, pub2))

    %{connection_pid: connection_pid} = :sys.get_state(pid)
    Process.alive?(connection_pid)
  end

  test "available/1 should state the node as available" do
    {:ok, pub} = Crypto.generate_random_keypair()

    {:ok, pid} =
      Node.start_link(first_public_key: pub, last_public_key: pub, ip: "127.0.0.1", port: 3000)

    Node.available(pub)
    assert match?(%{availability: 1}, :sys.get_state(pid))
  end

  test "unavailable/1 should state the node as unavailable" do
    {:ok, pub} = Crypto.generate_random_keypair()

    {:ok, pid} =
      Node.start_link(first_public_key: pub, last_public_key: pub, ip: "127.0.0.1", port: 3000)

    Node.available(pub)
    Node.unavailable(pub)
    assert match?(%{availability: 0}, :sys.get_state(pid))
  end

  test "details/1 should retrieve the node information" do
    {:ok, pub} = Crypto.generate_random_keypair()
    {:ok, pub2} = Crypto.generate_random_keypair()

    {:ok, pid} =
      Node.start_link(first_public_key: pub, last_public_key: pub2, ip: "127.0.0.1", port: 3000)

    assert match?(%Node{}, Node.details(pub))
    assert match?(%Node{}, Node.details(pub2))
  end

  test "update_basics/4 should update the basic node information" do
    {:ok, pub} = Crypto.generate_random_keypair()

    {:ok, _pid} =
      Node.start_link(first_public_key: pub, last_public_key: pub, ip: "127.0.0.1", port: 3000)

    {:ok, pub2} = Crypto.generate_random_keypair()
    Node.update_basics(pub, pub2, "88.100.242.12", 3000)
    node = Node.details(pub)
    assert node.last_public_key == pub2
    assert node.ip == "88.100.242.12"
  end

  test "update_network_patch/2 should update the network patch" do
    {:ok, pub} = Crypto.generate_random_keypair()

    {:ok, _pid} =
      Node.start_link(first_public_key: pub, last_public_key: pub, ip: "127.0.0.1", port: 3000)

    Node.update_network_patch(pub, "AA0")
    %{network_patch: network_patch} = Node.details(pub)
    assert network_patch == "AA0"
  end

  test "update_average_availability/2 should update the average availability" do
    {:ok, pub} = Crypto.generate_random_keypair()

    {:ok, _pid} =
      Node.start_link(first_public_key: pub, last_public_key: pub, ip: "127.0.0.1", port: 3000)

    Node.update_average_availability(pub, 0.5)
    %{average_availability: average_availability} = Node.details(pub)
    assert average_availability == 0.5
  end

  test "should kill the connection pid after the crash" do
    #
    {:ok, pub} = Crypto.generate_random_keypair()

    {:ok, pid} =
      Node.start_link(first_public_key: pub, last_public_key: pub, ip: "127.0.0.1", port: 3000)

    Node.available(pub)

    %{connection_pid: connection_pid} = :sys.get_state(pid)

    Process.flag(:trap_exit, true)

    Process.exit(pid, :shutdown)
    Process.sleep(100)
    assert !Process.alive?(connection_pid)

    {:ok, _} =
      Node.start_link(first_public_key: pub, last_public_key: pub, ip: "127.0.0.1", port: 3000)

    assert match?(%{availability: 0}, Node.details(pub))
  end
end
