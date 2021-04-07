defmodule Uniris.ElectionTest do
  use UnirisCase

  alias Uniris.Election
  alias Uniris.Election.StorageConstraints
  alias Uniris.Election.ValidationConstraints

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData

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
        timestamp: ~U[2020-06-25 08:57:04.288413Z],
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
        timestamp: ~U[2020-06-25 08:58:32.781244Z],
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
          P2P.list_nodes(authorized?: true, availability: :global),
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
               %Node{first_public_key: "Node5", geo_patch: "E3A", average_availability: 0.9},
               %Node{first_public_key: "Node2", geo_patch: "BBB", average_availability: 0.9},
               %Node{first_public_key: "Node0", geo_patch: "AAA", average_availability: 0.7},
               %Node{first_public_key: "Node6", geo_patch: "F1A", average_availability: 0.5},
               %Node{first_public_key: "Node4", geo_patch: "FBA", average_availability: 0.4},
               %Node{first_public_key: "Node3", geo_patch: "AFC", average_availability: 0.8}
             ] =
               Election.storage_nodes("address", available_nodes, %StorageConstraints{
                 number_replicas: fn _ ->
                   3
                 end,
                 min_geo_patch: fn -> 4 end,
                 min_geo_patch_average_availability: fn -> 0.8 end
               })
    end
  end
end
