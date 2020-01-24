defmodule UnirisNetwork.P2P.NodeViewTest do
  use ExUnit.Case

  alias UnirisNetwork.P2P.NodeView
  alias UnirisCrypto, as: Crypto

  test "start_link/1 should create a new state machine and register it with the public key" do
    {:ok, pub} = Crypto.generate_random_keypair()
    {:ok, pid} = NodeView.start_link(pub)
    assert Process.alive?(pid)
    assert match?([{_, _}], Registry.lookup(UnirisNetwork.NodeViewRegistry, pub))
    assert match?(:idle, NodeView.status(pub))
  end

  test "connected/1 should state the node as available when he is idle" do
    {:ok, pub} = Crypto.generate_random_keypair()
    NodeView.start_link(pub)
    NodeView.connected(pub)
    assert match?(:available, NodeView.status(pub))
  end

  test "connected/1 should keep available state when he is already available" do
    {:ok, pub} = Crypto.generate_random_keypair()
    NodeView.start_link(pub)
    NodeView.connected(pub)
    NodeView.connected(pub)
    assert match?(:available, NodeView.status(pub))
  end

  test "disconnected/1 should state the node as unavailable when he is idle" do
    {:ok, pub} = Crypto.generate_random_keypair()
    NodeView.start_link(pub)
    NodeView.disconnected(pub)
    assert match?(:unavailable, NodeView.status(pub))
  end

  test "disconnected/1 should state the node as unavailable when he is available" do
    {:ok, pub} = Crypto.generate_random_keypair()
    NodeView.start_link(pub)
    NodeView.connected(pub)
    NodeView.disconnected(pub)
    assert match?(:unavailable, NodeView.status(pub))
  end

  test "disconnected/1 should keep unavailable state when he is already unavailable" do
    {:ok, pub} = Crypto.generate_random_keypair()
    NodeView.start_link(pub)
    NodeView.disconnected(pub)
    NodeView.disconnected(pub)
    assert match?(:unavailable, NodeView.status(pub))
  end

  test "connected/1 should state the node as connected when he is unavailable" do
    {:ok, pub} = Crypto.generate_random_keypair()
    NodeView.start_link(pub)
    NodeView.disconnected(pub)
    NodeView.connected(pub)
    assert match?(:available, NodeView.status(pub))
  end

  # test "should save the state in ets backup when the FSM crash" do
  #  {:ok, pub} = Crypto.generate_random_keypair()
  #  {:ok, pid} = FSM.start_link(pub)
  #  FSM.connected(pub)
  #  :gen_statem.stop(pid)
  #  assert match?([{_, :available}], :ets.lookup(:node_view_backup, pub))
  # end

  test "should restore from saved state after a crash" do
    {:ok, pub} = Crypto.generate_random_keypair()

    {:ok, pid} = NodeView.start_link(pub)
    NodeView.connected(pub)
    assert match?(:available, NodeView.status(pub))

    Process.flag(:trap_exit, true)

    Process.exit(pid, :shutdown)
    Process.sleep(100)
    [{_, state}] = :ets.lookup(:node_view_backup, pub)
    assert state == :available

    NodeView.start_link(pub)
    assert match?(:available, NodeView.status(pub))
  end
end
