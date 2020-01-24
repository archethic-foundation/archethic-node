defmodule UnirisNetwork.P2P.AtomicTest do
  use ExUnit.Case

  alias UnirisNetwork.P2P.Atomic
  alias UnirisNetwork.Node

  import Mox

  setup :verify_on_exit!

  setup do
    nodes = [
      %Node{
        ip: "",
        port: "",
        last_public_key: "key1",
        first_public_key: "key1",
        geo_patch: "001",
        availability: 1,
        average_availability: 1
      },
      %Node{
        ip: "",
        port: "",
        last_public_key: "key2",
        first_public_key: "key2",
        geo_patch: "F3D",
        availability: 1,
        average_availability: 1
      },
      %Node{
        ip: "",
        port: "",
        last_public_key: "key3",
        first_public_key: "key3",
        geo_patch: "A0B",
        availability: 1,
        average_availability: 1
      }
    ]

    {:ok, %{nodes: nodes}}
  end

  test "call/2 should return the data and invovled nodes when the atomic commitment is reach",
       %{nodes: nodes} do 
    stub(MockClient, :send, fn node, _ -> {:ok, {:ok, :fake_data}, node} end)

    assert {:ok, data, involved_nodes} = Atomic.call(nodes, "fake_request")

    assert data == :fake_data
    assert involved_nodes == nodes
  end


  test "call/2 should return data and only the involved nodes", %{nodes: nodes} do
    stub(MockClient, :send, fn node, _ ->
      case node.last_public_key do
        "key1" ->
          {:ok, {:ok, :fake_data}, node}
        _ ->
           raise "Unexpected error"
      end
    end)

    assert {:ok, data, invovled_nodes} = Atomic.call(nodes, "fake_request")
    assert length(invovled_nodes) == 1
  assert data == :fake_data
  end

  test "call/2 should return only the data when the atomic commitment is reached and when the result contains an error",
       %{nodes: nodes} do
    stub(MockClient, :send, fn node, _ -> {:ok, {:error, :invalid_data}, node} end)
    assert {:error, :invalid_data} = Atomic.call(nodes, "fake_request")
  end

  test "call/2 should return an error when the atomic commitment is not reached", %{
    nodes: nodes
  } do
    stub(MockClient, :send, fn node, _ ->
      case node.last_public_key do
        "key1" ->
          {:ok, {:ok, :fake_data}, node}

        _ ->
          {:ok, {:error, :invalid_data}, node}
      end
    end)

    assert {:error, :consensus_not_reached} = Atomic.call(nodes, "fake_request")
  end
 
  test "cast/2 should return :ok when the all the nodes acknowledge the message", %{nodes: nodes} do
    stub(MockClient, :send, fn node, _ -> {:ok, node} end)
    assert :ok = Atomic.cast(nodes, "fake_request")
  end

  test "cast/2 should return an error when not all the nodes acknowledge the message", %{nodes: nodes} do
    stub(MockClient, :send, fn node, _ ->
      case node.last_public_key do
        "key1" ->
          {:ok, node}
        "key2" ->
          raise "Unexpected error"
        "key3" ->
           {{:error, :network_issue}, node}
      end
    end)

    assert {:error, :network_issue} = Atomic.cast(nodes, "fake_request")
  end
end
