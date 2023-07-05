defmodule Archethic.MiningTest do
  use ArchethicCase

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.Mining

  alias Archethic.TransactionFactory

  import Mox

  describe "get_validation_nodes/1" do
    test "should get the list of nodes" do
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
               %Node{first_public_key: "node3"},
               %Node{first_public_key: "node4"},
               %Node{first_public_key: "node2"}
             ] = Mining.get_validation_nodes(tx)
    end

    test "should retry with only locally available nodes" do
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
               %Node{first_public_key: "node4"},
               %Node{first_public_key: "node2"},
               %Node{first_public_key: "node1"}
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
  end

  describe "valid_election?/2" do
    test "should return when the election is valid" do
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

      validation_nodes = Mining.get_validation_nodes(tx)

      current_date = DateTime.utc_now()
      sorting_seed = Election.validation_nodes_election_seed_sorting(tx, current_date)

      sorted_nodes =
        current_date
        |> P2P.authorized_and_available_nodes()
        |> Election.sort_validation_nodes(tx, sorting_seed)

      assert Mining.valid_election?(
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

      sorted_nodes =
        current_date
        |> P2P.authorized_and_available_nodes()
        |> Election.sort_validation_nodes(tx, sorting_seed)

      refute Mining.valid_election?(
               Enum.map(node_list, & &1.last_public_key),
               sorted_nodes
             )
    end
  end
end
