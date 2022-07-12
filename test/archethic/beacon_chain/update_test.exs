defmodule Archethic.BeaconChain.UpdateTest do
  use ArchethicCase

  alias Archethic.BeaconChain.Update

  alias Archethic.P2P.Node

  import Mox
  import GenServer

  test "should create new entries in map" do
    {:ok, pid} = Update.start_link([], [])
    me = self()

    MockClient
    |> stub(:send_message, fn _, _, _ ->
      send(me, :message_sent)
      {:ok, nil}
    end)

    nodes = [
      %Node{first_public_key: "123"},
      %Node{first_public_key: "456"}
    ]

    GenServer.cast(pid, {:subscribe, nodes, <<200>>})
    assert_receive :message_sent
    assert %{"123" => [<<200>>], "456" => [<<200>>]} = :sys.get_state(pid)
  end

  test "should not duplicate node key" do
    {:ok, pid} = Update.start_link([], [])
    me = self()

    MockClient
    |> stub(:send_message, fn _, _, _ ->
      send(me, :message_sent)
      {:ok, nil}
    end)

    nodes = [%Node{first_public_key: "123"}]

    GenServer.cast(pid, {:subscribe, nodes, <<200>>})
    assert_receive :message_sent
    assert %{"123" => [<<200>>]} = :sys.get_state(pid)

    GenServer.cast(pid, {:subscribe, nodes, <<200>>})
    refute_receive :message_sent
    assert %{"123" => [<<200>>]} = :sys.get_state(pid)
  end

  test "should add subset to node" do
    {:ok, pid} = Update.start_link([], [])
    me = self()

    MockClient
    |> stub(:send_message, fn _, _, _ ->
      send(me, :message_sent)
      {:ok, nil}
    end)

    nodes = [%Node{first_public_key: "123"}]

    GenServer.cast(pid, {:subscribe, nodes, <<200>>})
    assert_receive :message_sent
    assert %{"123" => [<<200>>]} = :sys.get_state(pid)

    GenServer.cast(pid, {:subscribe, nodes, <<100>>})
    assert_receive :message_sent
    assert %{"123" => [<<100>>, <<200>>]} = :sys.get_state(pid)
  end

  test "should delete node from state" do
    {:ok, pid} = Update.start_link([], [])

    MockClient
    |> stub(:send_message, fn _, _, _ -> {:ok, nil} end)

    nodes = [
      %Node{first_public_key: "123"},
      %Node{first_public_key: "456"}
    ]

    GenServer.cast(pid, {:subscribe, nodes, <<200>>})
    assert %{"123" => [<<200>>], "456" => [<<200>>]} = :sys.get_state(pid)

    GenServer.cast(pid, {:unsubscribe, "123"})
    assert %{"456" => [<<200>>]} = :sys.get_state(pid)
  end
end
