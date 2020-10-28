defmodule Uniris.PubSubTest do
  use ExUnit.Case

  alias Uniris.P2P.Node

  alias Uniris.PubSub
  alias Uniris.PubSubRegistry

  test "register_to_new_transaction/0 should register the current process in the registry" do
    assert {:ok, _} = PubSub.register_to_new_transaction()
    pids = Enum.map(Registry.lookup(PubSubRegistry, :new_transaction), &elem(&1, 0))
    assert self() in pids
  end

  test "register_to_new_transaction_by_address/1 should register the current process in the registry" do
    assert {:ok, _} = PubSub.register_to_new_transaction_by_address("@Alice2")
    pids = Enum.map(Registry.lookup(PubSubRegistry, {:new_transaction, "@Alice2"}), &elem(&1, 0))
    assert self() in pids
  end

  test "register_to_new_transaction_by_type/1 should register the current process in the registry" do
    assert {:ok, _} = PubSub.register_to_new_transaction_by_type(:node)
    pids = Enum.map(Registry.lookup(PubSubRegistry, {:new_transaction, :node}), &elem(&1, 0))
    assert self() in pids
  end

  test "register_to_node_update/0 should register the current process in the registry" do
    assert {:ok, _} = PubSub.register_to_node_update()
    pids = Enum.map(Registry.lookup(PubSubRegistry, :node_update), &elem(&1, 0))
    assert self() in pids
  end

  test "register_to_code_proposal_deployment/1 should register the current process in the registry" do
    assert {:ok, _} = PubSub.register_to_code_proposal_deployment("@Prop1")

    pids =
      Enum.map(
        Registry.lookup(PubSubRegistry, {:code_proposal_deployment, "@Prop1"}),
        &elem(&1, 0)
      )

    assert self() in pids
  end

  describe "notify_new_transaction/3" do
    test "should  notify subscribers for all transactions" do
      {:ok, _} = PubSub.register_to_new_transaction()
      timestamp = DateTime.utc_now()
      assert :ok = PubSub.notify_new_transaction("@Alice2", :transfer, timestamp)

      assert_receive {:new_transaction, "@Alice2", :transfer, timestamp}
    end

    test "should  notify subscribers for a given address" do
      {:ok, _} = PubSub.register_to_new_transaction_by_address("@Alice2")
      timestamp = DateTime.utc_now()
      assert :ok = PubSub.notify_new_transaction("@Alice2", :transfer, timestamp)

      assert_receive {:new_transaction, "@Alice2"}
    end

    test "should  notify subscribers for a given type" do
      {:ok, _} = PubSub.register_to_new_transaction_by_type(:transfer)
      timestamp = DateTime.utc_now()
      assert :ok = PubSub.notify_new_transaction("@Alice2", :transfer, timestamp)

      assert_receive {:new_transaction, "@Alice2", :transfer}
    end
  end

  test "notify_new_transaction/1 should notify subscribers for new addresses" do
    {:ok, _} = PubSub.register_to_new_transaction()
    assert :ok = PubSub.notify_new_transaction("@Alice2")

    assert_receive {:new_transaction, "@Alice2"}
  end

  test "notify_node_update/1 should notify subscribers for node changes" do
    {:ok, _} = PubSub.register_to_node_update()
    node = %Node{ip: {127, 0, 0, 1}}
    assert :ok = PubSub.notify_node_update(node)
    assert_receive {:node_update, node}
  end

  test "notify_code_proposal_deployment/3 should notify subscribers for code deployment" do
    {:ok, _} = PubSub.register_to_code_proposal_deployment()
    assert :ok = PubSub.notify_code_proposal_deployment("@Prop1", 3094, 4039)
    assert_receive {:proposal_deployment, "@Prop1", 3094, 4039}
  end
end
