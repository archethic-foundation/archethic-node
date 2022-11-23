defmodule Archethic.SelfRepair.NotifierTest do
  @moduledoc false
  use ArchethicCase

  import Mox

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.ShardRepair
  alias Archethic.P2P.Node

  alias Archethic.SelfRepair.Notifier

  alias Archethic.TransactionChain.Transaction

  test "new_storage_nodes/2 should return new election" do
    node1 = %Node{
      first_public_key: "node1",
      last_public_key: "node1",
      authorized?: true,
      authorization_date: DateTime.utc_now(),
      available?: true,
      geo_patch: "AAA"
    }

    node2 = %Node{
      first_public_key: "node2",
      last_public_key: "node2",
      authorized?: true,
      authorization_date: DateTime.utc_now(),
      available?: true,
      geo_patch: "AAA"
    }

    node3 = %Node{
      first_public_key: "node3",
      last_public_key: "node3",
      authorized?: true,
      authorization_date: DateTime.utc_now(),
      available?: true,
      geo_patch: "AAA"
    }

    node4 = %Node{
      first_public_key: "node4",
      last_public_key: "node4",
      authorized?: true,
      authorization_date: DateTime.utc_now(),
      available?: true,
      geo_patch: "AAA"
    }

    P2P.add_and_connect_node(node1)
    P2P.add_and_connect_node(node2)
    P2P.add_and_connect_node(node3)
    P2P.add_and_connect_node(node4)

    prev_storage_nodes = ["node1", "node2", "node3"]
    unavailable_nodes = ["node2", "node3"]

    assert {"Alice1", ["node4"]} =
             Notifier.new_storage_nodes({"Alice1", prev_storage_nodes}, unavailable_nodes)
  end

  test "map_last_address_for_node/1 should create a map with last address for each node" do
    tab = [
      {"Alice1", ["node1", "node2"]},
      {"Alice2", ["node1", "node3"]},
      {"Alice3", ["node1"]},
      {"Alice4", ["node4"]},
      {"Alice5", ["node3"]}
    ]

    expected = %{
      "node1" => "Alice3",
      "node2" => "Alice1",
      "node3" => "Alice5",
      "node4" => "Alice4"
    }

    assert ^expected = Notifier.map_last_address_for_node(tab)
  end

  test "repair_transactions/1 should send message to new storage nodes" do
    node = %Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      authorized?: true,
      authorization_date: DateTime.utc_now(),
      available?: true,
      geo_patch: "AAA"
    }

    P2P.add_and_connect_node(node)

    nodes =
      Enum.reduce(1..50, [node], fn nb, acc ->
        node = %Node{
          first_public_key: "node#{nb}",
          last_public_key: "node#{nb}",
          authorized?: true,
          authorization_date: DateTime.utc_now(),
          available?: true,
          geo_patch: "#{Integer.to_string(nb, 16)}A"
        }

        P2P.add_and_connect_node(node)

        [node | acc]
      end)

    # Take nodes in election of Alice2 but not in the one of Alice3
    elec1 = Election.chain_storage_nodes("Alice2", nodes)
    elec2 = Election.chain_storage_nodes("Alice3", nodes)

    diff_nodes = elec1 -- elec2

    unavailable_nodes = Enum.take(diff_nodes, 2) |> Enum.map(& &1.first_public_key)

    # New possible storage nodes for Alice2
    new_possible_nodes = (nodes -- elec1) |> Enum.map(& &1.first_public_key)

    MockDB
    |> stub(:stream_first_addresses, fn -> ["Alice1", "Bob1"] end)
    |> stub(:get_transaction_chain, fn
      "Alice1", _, _ ->
        {[
           %Transaction{address: "Alice1"},
           %Transaction{address: "Alice2"},
           %Transaction{address: "Alice3"}
         ], false, nil}

      "Bob1", _, _ ->
        {[
           %Transaction{address: "Bob1"},
           %Transaction{address: "Bob2"},
           %Transaction{address: "Bob3"}
         ], false, nil}
    end)

    me = self()

    MockClient
    |> stub(:send_message, fn
      node, %ShardRepair{first_address: "Alice1", last_address: "Alice2"}, _ ->
        if Enum.member?(new_possible_nodes, node.first_public_key) do
          send(me, :new_node)
        end

      _, _, _ ->
        {:ok, %Ok{}}
    end)

    Notifier.repair_transactions(unavailable_nodes)

    # expect to receive 2 new node for Alice2
    assert_receive :new_node
  end
end
