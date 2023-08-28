defmodule Archethic.ElectionTest do
  use ArchethicCase

  alias Archethic.Election
  alias Archethic.Election.StorageConstraints
  alias Archethic.Election.ValidationConstraints

  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  doctest Election

  describe "validation_nodes/4" do
    test "should change for new transaction" do
      authorized_nodes = [
        %Node{
          first_public_key: "Node0",
          last_public_key: "Node0",
          available?: true,
          geo_patch: "AAA"
        },
        %Node{
          first_public_key: "Node1",
          last_public_key: "Node1",
          available?: true,
          geo_patch: "CCC"
        },
        %Node{
          first_public_key: "Node2",
          last_public_key: "Node2",
          available?: true,
          geo_patch: "CCC"
        },
        %Node{
          first_public_key: "Node3",
          last_public_key: "Node3",
          available?: true,
          geo_patch: "F24"
        }
      ]

      tx1 = %Transaction{
        address:
          <<0, 120, 195, 32, 77, 84, 215, 196, 116, 215, 56, 141, 40, 54, 226, 48, 66, 254, 119,
            11, 73, 77, 243, 125, 62, 94, 133, 67, 9, 253, 45, 134, 89>>,
        type: :transfer,
        data: %TransactionData{},
        previous_public_key:
          <<0, 239, 240, 90, 182, 66, 190, 68, 20, 250, 131, 83, 190, 29, 184, 177, 52, 166, 207,
            80, 193, 110, 57, 6, 199, 152, 184, 24, 178, 179, 11, 164, 150>>,
        previous_signature:
          <<200, 70, 0, 25, 105, 111, 15, 161, 146, 188, 100, 234, 147, 62, 127, 8, 152, 60, 66,
            169, 113, 255, 51, 112, 59, 200, 61, 63, 128, 228, 111, 104, 47, 15, 81, 185, 179, 36,
            59, 86, 171, 7, 138, 199, 203, 252, 50, 87, 160, 107, 119, 131, 121, 11, 239, 169, 99,
            203, 76, 159, 158, 243, 133, 133>>,
        origin_signature:
          <<162, 223, 100, 72, 17, 56, 99, 212, 78, 132, 166, 81, 127, 91, 214, 143, 221, 32, 106,
            189, 247, 64, 183, 27, 55, 142, 254, 72, 47, 215, 34, 108, 233, 55, 35, 94, 49, 165,
            180, 248, 229, 160, 229, 220, 191, 35, 80, 127, 213, 240, 195, 185, 165, 89, 172, 97,
            170, 217, 57, 254, 125, 127, 62, 169>>
      }

      first_election =
        Election.validation_nodes(
          tx1,
          "sorting_seed",
          authorized_nodes,
          ValidationConstraints.new()
        )

      tx2 = %Transaction{
        address:
          <<0, 120, 195, 32, 77, 84, 215, 196, 116, 215, 56, 141, 40, 54, 226, 48, 66, 254, 119,
            11, 73, 77, 243, 125, 62, 94, 133, 67, 9, 253, 45, 134, 89>>,
        type: :transfer,
        data: %TransactionData{},
        previous_public_key:
          <<0, 239, 240, 90, 182, 66, 190, 68, 20, 250, 131, 83, 190, 29, 184, 177, 52, 166, 207,
            80, 193, 110, 57, 6, 199, 152, 184, 24, 178, 179, 11, 164, 150>>,
        previous_signature:
          <<200, 70, 0, 25, 105, 111, 15, 161, 146, 188, 100, 234, 147, 62, 127, 8, 152, 60, 66,
            169, 113, 255, 51, 112, 59, 200, 61, 63, 128, 228, 111, 104, 47, 15, 81, 185, 179, 36,
            59, 86, 171, 7, 138, 199, 203, 252, 50, 87, 160, 107, 119, 131, 121, 11, 239, 169, 99,
            203, 76, 159, 158, 243, 133, 133>>,
        origin_signature:
          <<162, 223, 100, 72, 17, 56, 99, 212, 78, 132, 166, 81, 127, 91, 214, 143, 221, 32, 106,
            189, 247, 64, 183, 27, 55, 142, 254, 72, 47, 215, 34, 108, 233, 55, 35, 94, 49, 165,
            180, 248, 229, 160, 229, 220, 191, 35, 80, 127, 213, 240, 195, 185, 165, 89, 172, 97,
            170, 217, 57, 254, 125, 127, 62, 169>>
      }

      second_election =
        Election.validation_nodes(
          tx2,
          "daily_nonce_proof",
          authorized_nodes,
          ValidationConstraints.new()
        )

      assert Enum.map(first_election, & &1.last_public_key) !=
               Enum.map(second_election, & &1.last_public_key)
    end
  end

  describe "storage_nodes/1" do
    test "should return storage nodes according to the constraints provided" do
      available_nodes = [
        %Node{
          first_public_key: "Node0",
          last_public_key: "Node0",
          geo_patch: "AAA",
          average_availability: 0.7
        },
        %Node{
          first_public_key: "Node1",
          last_public_key: "Node1",
          geo_patch: "CCC",
          average_availability: 0.1
        },
        %Node{
          first_public_key: "Node2",
          last_public_key: "Node2",
          geo_patch: "BBB",
          average_availability: 0.9
        },
        %Node{
          first_public_key: "Node3",
          last_public_key: "Node3",
          geo_patch: "AFC",
          average_availability: 0.8
        },
        %Node{
          first_public_key: "Node4",
          last_public_key: "Node4",
          geo_patch: "FBA",
          average_availability: 0.4
        },
        %Node{
          first_public_key: "Node5",
          last_public_key: "Node5",
          geo_patch: "E3A",
          average_availability: 0.9
        },
        %Node{
          first_public_key: "Node6",
          last_public_key: "Node6",
          geo_patch: "F1A",
          average_availability: 0.5
        }
      ]

      assert [
               %Node{first_public_key: "Node1", geo_patch: "CCC", average_availability: 0.1},
               %Node{first_public_key: "Node3", geo_patch: "AFC", average_availability: 0.8},
               %Node{first_public_key: "Node2", geo_patch: "BBB", average_availability: 0.9},
               %Node{first_public_key: "Node5", geo_patch: "E3A", average_availability: 0.9}
             ] =
               Election.storage_nodes("address", available_nodes, %StorageConstraints{
                 number_replicas: fn _ ->
                   3
                 end,
                 min_geo_patch: fn -> 3 end,
                 min_geo_patch_average_availability: fn -> 0.8 end
               })
    end
  end

  describe "chain_storage_node/2" do
    test "when the transaction is a network transaction, all the nodes are involved" do
      nodes =
        Enum.map(1..200, fn i ->
          %Node{
            ip: {88, 130, 19, i},
            port: 3000 + i,
            last_public_key: :crypto.strong_rand_bytes(32),
            first_public_key: :crypto.strong_rand_bytes(32),
            geo_patch: random_patch(),
            available?: true,
            authorized?: rem(i, 7) == 0,
            authorization_date: DateTime.utc_now(),
            enrollment_date: DateTime.utc_now(),
            reward_address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
          }
        end)

      chain_storage_nodes = Election.chain_storage_nodes_with_type("@Node1", :node, nodes)
      node_public_keys = Enum.map(nodes, & &1.first_public_key)

      assert Enum.all?(
               chain_storage_nodes,
               &(&1.first_public_key in node_public_keys)
             )
    end

    test "when the transaction is not a network transaction, a shared of nodes is used" do
      nodes =
        Enum.map(1..200, fn i ->
          %Node{
            ip: {88, 130, 19, i},
            port: 3000 + i,
            last_public_key: :crypto.strong_rand_bytes(32),
            first_public_key: :crypto.strong_rand_bytes(32),
            geo_patch: random_patch(),
            available?: true,
            authorized?: rem(i, 7) == 0,
            authorization_date: DateTime.utc_now(),
            enrollment_date: DateTime.utc_now(),
            reward_address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
          }
        end)

      chain_storage_nodes =
        Election.chain_storage_nodes_with_type("@Alice2", :transfer, nodes)
        |> Enum.map(& &1.last_public_key)

      assert !Enum.all?(nodes, &(&1.last_public_key in chain_storage_nodes))
    end
  end

  test "beacon_storage_nodes/2 should list the beacon storage nodes authorized before the transaction timestamp" do
    nodes = [
      %Node{
        ip: {88, 130, 19, 0},
        port: 3002,
        last_public_key: :crypto.strong_rand_bytes(32),
        first_public_key: :crypto.strong_rand_bytes(32),
        geo_patch: random_patch(),
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        enrollment_date: DateTime.utc_now(),
        reward_address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
      },
      %Node{
        ip: {88, 130, 19, 1},
        port: 3005,
        last_public_key: :crypto.strong_rand_bytes(32),
        first_public_key: :crypto.strong_rand_bytes(32),
        geo_patch: random_patch(),
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        reward_address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
      },
      %Node{
        ip: {88, 130, 19, 2},
        port: 3008,
        last_public_key: :crypto.strong_rand_bytes(32),
        first_public_key: :crypto.strong_rand_bytes(32),
        geo_patch: random_patch(),
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-10),
        enrollment_date: DateTime.utc_now(),
        reward_address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
      }
    ]

    beacon_storage_nodes = Election.beacon_storage_nodes("@Alice2", DateTime.utc_now(), nodes)

    beacon_storage_nodes_ip = Enum.map(beacon_storage_nodes, & &1.ip)
    assert Enum.all?([{88, 130, 19, 2}, {88, 130, 19, 0}], &(&1 in beacon_storage_nodes_ip))
  end

  defp random_patch do
    list_char = Enum.concat([?0..?9, ?A..?F])
    Enum.take_random(list_char, 3) |> List.to_string()
  end
end
