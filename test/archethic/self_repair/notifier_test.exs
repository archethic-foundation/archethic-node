defmodule Archethic.SelfRepair.NotifierTest do
  @moduledoc false
  use ArchethicCase

  import Mox

  alias Archethic.BeaconChain.SummaryAggregate
  alias Archethic.BeaconChain.SummaryTimer

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetBeaconSummariesAggregate
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.ShardRepair
  alias Archethic.P2P.Node

  alias Archethic.SelfRepair.Notifier

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  test "filter_nodes_to_notify/1 should return new nodes in election" do
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

    prev_storage_nodes = ["node2", "node3"]
    prev_io_nodes = []
    new_storage_nodes = ["node4", "node2", "node1"]
    new_io_nodes = []

    assert %{
             address: "Alice1",
             genesis_address: "Alice0",
             new_io_nodes: [],
             new_storage_nodes: ["node4", "node1"]
           } =
             Notifier.filter_nodes_to_notify(%{
               address: "Alice1",
               genesis_address: "Alice0",
               new_io_nodes: new_io_nodes,
               new_storage_nodes: new_storage_nodes,
               prev_io_nodes: prev_io_nodes,
               prev_storage_nodes: prev_storage_nodes
             })
  end

  test "map_last_address_for_node/1 should create a map with last address for each node" do
    tab = [
      %{
        address: "Alice1",
        genesis_address: "Alice0",
        new_storage_nodes: ["node1"],
        new_io_nodes: ["node3"]
      },
      %{
        address: "Alice2",
        genesis_address: "Alice0",
        new_storage_nodes: [],
        new_io_nodes: ["node1"]
      },
      %{
        address: "Alice3",
        genesis_address: "Alice0",
        new_storage_nodes: ["node1"],
        new_io_nodes: ["node3"]
      },
      %{
        address: "Alice4",
        genesis_address: "Alice0",
        new_storage_nodes: ["node4"],
        new_io_nodes: ["node2"]
      },
      %{
        address: "Alice5",
        genesis_address: "Alice0",
        new_storage_nodes: ["node3"],
        new_io_nodes: []
      }
    ]

    expected = %{
      "node1" => %{genesis_address: "Alice0", last_address: "Alice3", io_addresses: ["Alice2"]},
      "node2" => %{genesis_address: "Alice0", last_address: nil, io_addresses: ["Alice4"]},
      "node3" => %{
        genesis_address: "Alice0",
        last_address: "Alice5",
        io_addresses: ["Alice3", "Alice1"]
      },
      "node4" => %{genesis_address: "Alice0", last_address: "Alice4", io_addresses: []}
    }

    assert ^expected = Notifier.map_last_addresses_for_node(tab)
  end

  test "repair_transactions/2 should send message to new storage nodes" do
    node = %Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      authorized?: true,
      authorization_date: DateTime.utc_now(),
      available?: true,
      geo_patch: "AAA"
    }

    P2P.add_and_connect_node(node)

    previous_nodes =
      Enum.map(1..50, fn nb ->
        node = %Node{
          first_public_key: "node#{nb}",
          last_public_key: "node#{nb}",
          authorized?: true,
          authorization_date: DateTime.utc_now(),
          available?: true,
          geo_patch: "#{Integer.to_string(nb, 16)}A"
        }

        P2P.add_and_connect_node(node)

        node
      end)

    previous_nodes = [node | previous_nodes]

    # Take nodes in election of Alice2 but not in the one of Alice3
    elec1 = Election.chain_storage_nodes("Alice2", previous_nodes)
    elec2 = Election.chain_storage_nodes("Alice3", previous_nodes)

    diff_nodes = elec1 -- elec2

    unavailable_nodes = Enum.take(diff_nodes, 2) |> Enum.map(& &1.first_public_key)

    new_nodes = Enum.reject(previous_nodes, &(&1.first_public_key in unavailable_nodes))

    # New possible storage nodes for Alice2
    new_possible_nodes = (previous_nodes -- elec1) |> Enum.map(& &1.first_public_key)

    MockDB
    |> stub(:list_first_addresses, fn -> ["Alice1"] end)
    |> stub(:stream_chain, fn
      "Alice1", _ ->
        [
          %Transaction{
            address: "Alice1",
            validation_stamp: %ValidationStamp{
              genesis_address: "Alice0",
              ledger_operations: %LedgerOperations{transaction_movements: []}
            }
          },
          %Transaction{
            address: "Alice2",
            validation_stamp: %ValidationStamp{
              genesis_address: "Alice0",
              ledger_operations: %LedgerOperations{transaction_movements: []}
            }
          },
          %Transaction{
            address: "Alice3",
            validation_stamp: %ValidationStamp{
              genesis_address: "Alice0",
              ledger_operations: %LedgerOperations{transaction_movements: []}
            }
          }
        ]
    end)

    me = self()

    MockClient
    |> stub(:send_message, fn
      node, %ShardRepair{genesis_address: "Alice0", storage_address: "Alice2"}, _ ->
        if Enum.member?(new_possible_nodes, node.first_public_key) do
          send(me, :new_node)
        end

      _, _, _ ->
        {:ok, %Ok{}}
    end)

    Notifier.repair_transactions(previous_nodes, new_nodes)

    # Expect to receive only 1 new node for Alice2
    assert_receive :new_node
    refute_receive :new_node, 200
  end

  test "repair_summaries_aggregate/2 should store beacon aggregate" do
    enrollment_date = DateTime.utc_now() |> DateTime.add(-10, :minute)

    node = %Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      geo_patch: "AAA",
      network_patch: "AAA",
      authorized?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-11, :minute),
      available?: true,
      enrollment_date: enrollment_date
    }

    P2P.add_and_connect_node(node)

    nodes =
      Enum.map(1..9, fn nb ->
        %Node{
          first_public_key: "node#{nb}",
          last_public_key: "node#{nb}",
          geo_patch: "AAA",
          network_patch: "AAA",
          authorized?: true,
          authorization_date: DateTime.utc_now(),
          available?: true
        }
      end)

    nodes = [node | nodes]

    Application.put_env(:archethic, SummaryTimer, interval: "0 * * * *")

    [first_date | rest] = SummaryTimer.next_summaries(enrollment_date) |> Enum.to_list()
    random_date = Enum.random(rest)

    me = self()

    MockDB
    |> stub(:get_beacon_summaries_aggregate, fn
      summary_time when summary_time in [first_date, random_date] ->
        {:error, :not_exists}

      summary_time ->
        {:ok, %SummaryAggregate{summary_time: summary_time}}
    end)
    |> expect(:write_beacon_summaries_aggregate, 2, fn
      %SummaryAggregate{summary_time: summary_time} when summary_time == first_date ->
        send(me, :write_first_date)

      %SummaryAggregate{summary_time: summary_time} when summary_time == random_date ->
        send(me, :write_random_date)

      _ ->
        send(me, :unexpected)
    end)

    MockClient
    |> stub(:send_message, fn _, %GetBeaconSummariesAggregate{date: summary_time}, _ ->
      {:ok, %SummaryAggregate{summary_time: summary_time}}
    end)

    Notifier.repair_summaries_aggregate(nodes, nodes)

    assert_receive :write_first_date
    assert_receive :write_random_date
    refute_receive :unexpected
  end
end
