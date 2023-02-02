defmodule Archethic.BeaconChain.UpdateTest do
  use ArchethicCase

  alias Archethic.BeaconChain.Update, as: BeaconUpdate
  alias Archethic.P2P.Message.NewBeaconSlot
  alias Archethic.P2P.Message.Ok

  alias Archethic.P2P.Node

  import Mox

  alias Archethic.P2P.Message.RegisterBeaconUpdates

  describe "Beacon Update test" do
    setup do
      BeaconUpdate.unsubscribe()

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

      assert %{"123" => [<<202>>], "456" => [<<202>>]} = :sys.get_state(BeaconUpdate)
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

      assert %{"123" => [<<203>>]} = :sys.get_state(BeaconUpdate)
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

      assert %{"123" => [<<100>>, <<205>>]} = :sys.get_state(BeaconUpdate)
    end

    test "should delete node from state" do
      MockClient
      |> stub(:send_message, fn
        %Node{first_public_key: node_public_key},
        %RegisterBeaconUpdates{node_public_key: _, subset: subset},
        _timeout ->
          assert {node_public_key, subset} in [
                   {"123", <<150>>},
                   {"456", <<150>>},
                   {"789", <<150>>}
                 ]

          {:ok, nil}

        _, %NewBeaconSlot{}, _ ->
          {:ok, %Ok{}}
      end)

      nodes = [
        %Node{first_public_key: "123"},
        %Node{first_public_key: "456"},
        %Node{first_public_key: "789"}
      ]

      BeaconUpdate.subscribe(nodes, <<150>>)

      assert %{"123" => [<<150>>], "456" => [<<150>>], "789" => [<<150>>]} =
               :sys.get_state(BeaconUpdate)

      BeaconUpdate.unsubscribe("123")

      assert %{"456" => [<<150>>], "789" => [<<150>>]} = :sys.get_state(BeaconUpdate)

      BeaconUpdate.unsubscribe()

      assert %{} = :sys.get_state(BeaconUpdate)
    end
  end
end
