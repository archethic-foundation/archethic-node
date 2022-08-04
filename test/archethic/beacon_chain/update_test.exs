defmodule Archethic.BeaconChain.UpdateTest do
  use ArchethicCase

  alias Archethic.BeaconChain.Update, as: BeaconUpdate

  alias Archethic.P2P.Node

  import Mox

  alias Archethic.P2P.Message.RegisterBeaconUpdates

  describe "Beacon Update test" do
    setup do
      case Process.whereis(BeaconUpdate) do
        nil -> start_supervised({BeaconUpdate, [[], []]})
        _pid -> nil
      end

      :ok
    end

    test "should create new entries in map" do
      nodes = [
        %Node{first_public_key: "123"},
        %Node{first_public_key: "456"}
      ]

      MockClient
      |> stub(:send_message, fn
        %Node{first_public_key: node_public_key},
        %RegisterBeaconUpdates{node_public_key: _, subset: subset},
        _timeout ->
          assert {node_public_key, subset} in [{"123", <<202>>}, {"456", <<202>>}]
          {:ok, nil}
      end)

      BeaconUpdate.subscribe(nodes, <<202>>)

      assert 1 = Enum.count(Map.get(:sys.get_state(BeaconUpdate), "123"), &(&1 == <<202>>))

      assert 1 = Enum.count(Map.get(:sys.get_state(BeaconUpdate), "456"), &(&1 == <<202>>))
    end

    test "should not duplicate node key" do
      MockClient
      |> stub(:send_message, fn
        %Node{first_public_key: node_public_key},
        %RegisterBeaconUpdates{node_public_key: _, subset: subset},
        _timeout ->
          assert {node_public_key, subset} in [{"123", <<203>>}]
          {:ok, nil}
      end)

      nodes = [%Node{first_public_key: "123"}]

      BeaconUpdate.subscribe(nodes, <<203>>)
      BeaconUpdate.subscribe(nodes, <<203>>)

      assert 1 == Enum.count(Map.get(:sys.get_state(BeaconUpdate), "123"), &(&1 == <<203>>))
    end

    test "should add subset to node" do
      MockClient
      |> stub(:send_message, fn
        %Node{first_public_key: node_public_key},
        %RegisterBeaconUpdates{node_public_key: _, subset: subset},
        _timeout ->
          assert {node_public_key, subset} in [{"123", <<205>>}, {"123", <<100>>}]
          {:ok, nil}
      end)

      nodes = [%Node{first_public_key: "123"}]

      BeaconUpdate.subscribe(nodes, <<205>>)
      BeaconUpdate.subscribe(nodes, <<100>>)

      assert 1 ==
               Enum.count(
                 Map.get(:sys.get_state(BeaconUpdate), "123"),
                 &(&1 == <<205>>)
               )

      assert 1 == Enum.count(Map.get(:sys.get_state(BeaconUpdate), "123"), &(&1 == <<100>>))
    end

    test "should delete node from state" do
      MockClient
      |> stub(:send_message, fn
        %Node{first_public_key: node_public_key},
        %RegisterBeaconUpdates{node_public_key: _, subset: subset},
        _timeout ->
          assert {node_public_key, subset} in [{"123", <<150>>}, {"456", <<150>>}]
          {:ok, nil}
      end)

      nodes = [
        %Node{first_public_key: "123"},
        %Node{first_public_key: "456"}
      ]

      BeaconUpdate.subscribe(nodes, <<150>>)

      assert 1 ==
               Enum.count(Map.get(:sys.get_state(BeaconUpdate), "123"), &(&1 == <<150>>))

      assert 1 ==
               Enum.count(Map.get(:sys.get_state(BeaconUpdate), "456"), &(&1 == <<150>>))

      BeaconUpdate.unsubscribe("123")

      assert 1 ==
               Enum.count(Map.get(:sys.get_state(BeaconUpdate), "456"), &(&1 == <<150>>))
    end
  end
end
