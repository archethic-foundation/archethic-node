defmodule Archethic.MiningTest do
  use ArchethicCase

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.Mining

  alias Archethic.TransactionFactory
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  import Mox

  describe "get_validation_nodes/1" do
    test "should get the min of validation with overbook" do
      node_list = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          geo_patch: "AAA",
          first_public_key: "node1",
          last_public_key: "node1",
          authorized?: true,
          authorization_date: DateTime.utc_now(),
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3001,
          geo_patch: "BCE",
          first_public_key: "node2",
          last_public_key: "node2",
          authorized?: true,
          authorization_date: DateTime.utc_now(),
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3002,
          geo_patch: "FAC",
          first_public_key: "node3",
          last_public_key: "node3",
          authorized?: true,
          authorization_date: DateTime.utc_now(),
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3003,
          geo_patch: "DEA",
          first_public_key: "node4",
          last_public_key: "node4",
          authorized?: true,
          authorization_date: DateTime.utc_now(),
          available?: true
        }
      ]

      Enum.each(node_list, &P2P.add_and_connect_node/1)

      tx = TransactionFactory.create_valid_transaction([], type: :node)

      assert [
               %Node{first_public_key: "node2"},
               %Node{first_public_key: "node1"},
               %Node{first_public_key: "node3"},
               %Node{first_public_key: "node4"}
             ] = Mining.get_validation_nodes(tx)
    end

    test "should retry with only locally available nodes and matching the constraints" do
      node_list = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          geo_patch: "AAA",
          first_public_key: "node1",
          last_public_key: "node1",
          authorized?: true,
          authorization_date: DateTime.utc_now(),
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3001,
          geo_patch: "BCE",
          first_public_key: "node2",
          last_public_key: "node2",
          authorized?: true,
          authorization_date: DateTime.utc_now(),
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3002,
          geo_patch: "FAC",
          first_public_key: "node3",
          last_public_key: "node3",
          authorized?: true,
          authorization_date: DateTime.utc_now(),
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3003,
          geo_patch: "DEA",
          first_public_key: "node4",
          last_public_key: "node4",
          authorized?: true,
          authorization_date: DateTime.utc_now(),
          available?: true
        }
      ]

      Enum.each(node_list, &P2P.add_and_connect_node/1)

      MockClient
      |> stub(:connected?, fn
        "node3" -> false
        _ -> true
      end)

      tx = TransactionFactory.create_valid_transaction([], type: :node)

      assert [
               %Node{first_public_key: "node2"},
               %Node{first_public_key: "node1"},
               %Node{first_public_key: "node4"}
             ] = Mining.get_validation_nodes(tx)
    end

    test "should retry with only locally available nodes but with nb of nodes less than the requirements" do
      node_list = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          geo_patch: "AAA",
          first_public_key: "node1",
          last_public_key: "node1",
          authorized?: true,
          authorization_date: DateTime.utc_now(),
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3001,
          geo_patch: "BCE",
          first_public_key: "node2",
          last_public_key: "node2",
          authorized?: true,
          authorization_date: DateTime.utc_now(),
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3002,
          geo_patch: "FAC",
          first_public_key: "node3",
          last_public_key: "node3",
          authorized?: true,
          authorization_date: DateTime.utc_now(),
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3003,
          geo_patch: "DEA",
          first_public_key: "node4",
          last_public_key: "node4",
          authorized?: true,
          authorization_date: DateTime.utc_now(),
          available?: true
        }
      ]

      Enum.each(node_list, &P2P.add_and_connect_node/1)

      MockClient
      |> stub(:connected?, fn
        "node3" -> false
        "node4" -> false
        _ -> true
      end)

      tx = TransactionFactory.create_valid_transaction([], type: :node)

      assert [
               %Node{first_public_key: "node2"},
               %Node{first_public_key: "node1"}
             ] = Mining.get_validation_nodes(tx)
    end

    test "should retry with only locally available nodes but with multiple nodes in the same geo patch" do
      date = ~U[2023-08-24 00:00:00Z]

      node_list = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          geo_patch: "AAA",
          first_public_key: "node1",
          last_public_key: "node1",
          authorized?: true,
          authorization_date: date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3001,
          geo_patch: "BCE",
          first_public_key: "node2",
          last_public_key: "node2",
          authorized?: true,
          authorization_date: date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3002,
          geo_patch: "FAC",
          first_public_key: "node3",
          last_public_key: "node3",
          authorized?: true,
          authorization_date: date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3003,
          geo_patch: "DEA",
          first_public_key: "node4",
          last_public_key: "node4",
          authorized?: true,
          authorization_date: date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          geo_patch: "ABC",
          first_public_key: "node5",
          last_public_key: "node5",
          authorized?: true,
          authorization_date: date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3001,
          geo_patch: "BAE",
          first_public_key: "node6",
          last_public_key: "node6",
          authorized?: true,
          authorization_date: date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          geo_patch: "FBC",
          first_public_key: "node7",
          last_public_key: "node7",
          authorized?: true,
          authorization_date: date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          geo_patch: "DAA",
          first_public_key: "node8",
          last_public_key: "node8",
          authorized?: true,
          authorization_date: date,
          available?: true
        }
      ]

      Enum.each(node_list, &P2P.add_and_connect_node/1)

      MockClient
      |> stub(:connected?, fn
        "node8" -> false
        "node3" -> false
        "node7" -> false
        "node4" -> false
        _ -> true
      end)

      tx =
        Transaction.new(
          :node,
          %TransactionData{},
          "seed",
          0
        )

      # Sorted list of nodes
      # node2 (BCE)
      # node1 (AAA)
      # node6 (BAE)
      # node8 (DAA)
      # node3 (FAC)
      # node5 (ABC)
      # node7 (FBC)
      # node4 (DEA)

      MockClient
      |> stub(:connected?, fn
        "node8" -> false
        "node3" -> false
        "node7" -> false
        "node4" -> false
        _ -> true
      end)

      # By removing the potential candidate for other geo patches,
      # we force the algorithm to run a second time
      # to accept node in the same patch (2nd digit allowance)

      assert [
               %Node{first_public_key: "node2", geo_patch: "BCE"},
               %Node{first_public_key: "node1", geo_patch: "AAA"},
               %Node{first_public_key: "node6", geo_patch: "BAE"}
             ] = Mining.get_validation_nodes(tx, date)
    end
  end

  describe "valid_election?/2" do
    test "should return when the election is valid" do
      current_date = ~U[2023-08-24 00:00:00Z]

      node_list = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          geo_patch: "AAA",
          first_public_key: "node1",
          last_public_key: "node1",
          authorized?: true,
          authorization_date: current_date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3001,
          geo_patch: "BCE",
          first_public_key: "node2",
          last_public_key: "node2",
          authorized?: true,
          authorization_date: current_date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3002,
          geo_patch: "FAC",
          first_public_key: "node3",
          last_public_key: "node3",
          authorized?: true,
          authorization_date: current_date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3003,
          geo_patch: "DEA",
          first_public_key: "node4",
          last_public_key: "node4",
          authorized?: true,
          authorization_date: current_date,
          available?: true
        }
      ]

      Enum.each(node_list, &P2P.add_and_connect_node/1)

      tx = TransactionFactory.create_valid_transaction([], type: :node)

      current_date = ~U[2023-08-24 00:00:00Z]

      validation_nodes = Mining.get_validation_nodes(tx, current_date)
      # Node2
      # Node1
      # Node3
      # Node4

      sorting_seed = Election.validation_nodes_election_seed_sorting(tx, current_date)

      sorted_nodes =
        current_date
        |> P2P.authorized_and_available_nodes()
        |> Election.sort_validation_nodes(tx, sorting_seed)

      # Node2
      # Node1
      # Node3
      # Node4

      assert Mining.valid_election?(
               tx,
               Enum.map(validation_nodes, & &1.last_public_key),
               sorted_nodes
             )
    end

    test "should return true when the election is valid after iteration" do
      date = ~U[2023-08-24 00:00:00Z]

      node_list = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          geo_patch: "AAA",
          first_public_key: "node1",
          last_public_key: "node1",
          authorized?: true,
          authorization_date: date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3001,
          geo_patch: "BCE",
          first_public_key: "node2",
          last_public_key: "node2",
          authorized?: true,
          authorization_date: date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3002,
          geo_patch: "FAC",
          first_public_key: "node3",
          last_public_key: "node3",
          authorized?: true,
          authorization_date: date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3003,
          geo_patch: "DEA",
          first_public_key: "node4",
          last_public_key: "node4",
          authorized?: true,
          authorization_date: date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          geo_patch: "ABC",
          first_public_key: "node5",
          last_public_key: "node5",
          authorized?: true,
          authorization_date: date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3001,
          geo_patch: "BAE",
          first_public_key: "node6",
          last_public_key: "node6",
          authorized?: true,
          authorization_date: date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          geo_patch: "FBC",
          first_public_key: "node7",
          last_public_key: "node7",
          authorized?: true,
          authorization_date: date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          geo_patch: "DAA",
          first_public_key: "node8",
          last_public_key: "node8",
          authorized?: true,
          authorization_date: date,
          available?: true
        }
      ]

      Enum.each(node_list, &P2P.add_and_connect_node/1)

      MockClient
      |> stub(:connected?, fn
        "node8" -> false
        "node3" -> false
        "node7" -> false
        "node4" -> false
        _ -> true
      end)

      tx = TransactionFactory.create_valid_transaction([], type: :node)

      validation_nodes = Mining.get_validation_nodes(tx, date)

      sorting_seed = Election.validation_nodes_election_seed_sorting(tx, date)

      sorted_nodes =
        date
        |> P2P.authorized_and_available_nodes()
        |> Election.sort_validation_nodes(tx, sorting_seed)

      assert Mining.valid_election?(
               tx,
               Enum.map(validation_nodes, & &1.last_public_key),
               sorted_nodes
             )
    end

    test "should return false when the public keys are not authorized nodes" do
      node_list = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          geo_patch: "AAA",
          first_public_key: "node1",
          last_public_key: "node1",
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3001,
          geo_patch: "BCE",
          first_public_key: "node2",
          last_public_key: "node2",
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3002,
          geo_patch: "FAC",
          first_public_key: "node3",
          last_public_key: "node3",
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3003,
          geo_patch: "DEA",
          first_public_key: "node4",
          last_public_key: "node4",
          available?: true
        }
      ]

      tx = TransactionFactory.create_valid_transaction([], type: :node)

      current_date = DateTime.utc_now()
      sorting_seed = Election.validation_nodes_election_seed_sorting(tx, current_date)

      #

      sorted_nodes =
        current_date
        |> P2P.authorized_and_available_nodes()
        |> Election.sort_validation_nodes(tx, sorting_seed)

      refute Mining.valid_election?(
               tx,
               Enum.map(node_list, & &1.last_public_key),
               sorted_nodes
             )
    end

    test "should return true when all the nodes are in the same geopatch" do
      date = ~U[2023-08-24 00:00:00Z]

      node_list = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          geo_patch: "000",
          first_public_key: "node1",
          last_public_key: "node1",
          authorized?: true,
          authorization_date: date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3001,
          geo_patch: "000",
          first_public_key: "node2",
          last_public_key: "node2",
          authorized?: true,
          authorization_date: date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3002,
          geo_patch: "000",
          first_public_key: "node3",
          last_public_key: "node3",
          authorized?: true,
          authorization_date: date,
          available?: true
        }
      ]

      Enum.each(node_list, &P2P.add_and_connect_node/1)

      tx = TransactionFactory.create_valid_transaction([], type: :node)

      sorting_seed = Election.validation_nodes_election_seed_sorting(tx, date)

      sorted_nodes = Election.sort_validation_nodes(node_list, tx, sorting_seed)

      assert Mining.valid_election?(
               tx,
               ["node2", "node1", "node3"],
               sorted_nodes
             )
    end

    test "should return false when the order is not respected" do
      date = ~U[2023-08-24 00:00:00Z]

      node_list = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          geo_patch: "AAA",
          first_public_key: "node1",
          last_public_key: "node1",
          authorized?: true,
          authorization_date: date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3001,
          geo_patch: "BCE",
          first_public_key: "node2",
          last_public_key: "node2",
          authorized?: true,
          authorization_date: date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3002,
          geo_patch: "FAC",
          first_public_key: "node3",
          last_public_key: "node3",
          authorized?: true,
          authorization_date: date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3003,
          geo_patch: "DEA",
          first_public_key: "node4",
          last_public_key: "node4",
          authorized?: true,
          authorization_date: date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          geo_patch: "ABC",
          first_public_key: "node5",
          last_public_key: "node5",
          authorized?: true,
          authorization_date: date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3001,
          geo_patch: "BAE",
          first_public_key: "node6",
          last_public_key: "node6",
          authorized?: true,
          authorization_date: date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          geo_patch: "FBC",
          first_public_key: "node7",
          last_public_key: "node7",
          authorized?: true,
          authorization_date: date,
          available?: true
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          geo_patch: "DAA",
          first_public_key: "node8",
          last_public_key: "node8",
          authorized?: true,
          authorization_date: date,
          available?: true
        }
      ]

      Enum.each(node_list, &P2P.add_and_connect_node/1)

      tx =
        Transaction.new(
          :node,
          %TransactionData{},
          "seed",
          0
        )

      sorting_seed = Election.validation_nodes_election_seed_sorting(tx, date)

      sorted_nodes = Election.sort_validation_nodes(node_list, tx, sorting_seed)

      # Sorted list of nodes
      # node2 (BCE)
      # node1 (AAA)
      # node6 (BAE)
      # node8 (DAA)
      # node3 (FAC)
      # node5 (ABC)
      # node7 (FBC)
      # node4 (DEA)

      refute Mining.valid_election?(
               tx,
               ["node1", "node2", "node6"],
               sorted_nodes
             )
    end
  end
end
