defmodule UnirisCore.ElectionTest do
  use UnirisCoreCase

  alias UnirisCore.Crypto
  alias UnirisCore.Election

  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node

  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData

  import Mox

  describe "validation_nodes/1" do
    test "should return available and authorized nodes" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "Node0",
        last_public_key: "Node0",
        authorized?: true,
        ready?: true,
        available?: true,
        geo_patch: "AAA"
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "Node1",
        last_public_key: "Node1",
        authorized?: false,
        ready?: true,
        available?: true,
        geo_patch: "CCC"
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "Node2",
        last_public_key: "Node2",
        authorized?: true,
        ready?: true,
        available?: false,
        geo_patch: "BBB"
      })

      assert [%Node{first_public_key: "Node0"}] =
               Election.validation_nodes(
                 Transaction.new(:transfer, %TransactionData{}, "seed", 0)
               )
    end

    test "should change for new transaction" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "Node0",
        last_public_key: "Node0",
        authorized?: true,
        ready?: true,
        available?: true,
        geo_patch: "AAA"
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "Node1",
        last_public_key: "Node1",
        authorized?: true,
        ready?: true,
        available?: true,
        geo_patch: "CCC"
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "Node2",
        last_public_key: "Node2",
        authorized?: true,
        ready?: true,
        available?: true,
        geo_patch: "BBB"
      })

      MockCrypto
      |> stub(:hash_with_daily_nonce, fn data -> Crypto.hash(data) end)

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

      first_election = Election.validation_nodes(tx1)

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

      second_election = Election.validation_nodes(tx2)

      assert Enum.map(first_election, & &1.last_public_key) !=
               Enum.map(second_election, & &1.last_public_key)
    end

    test "should select validation nodes with a least 3 geo zones and 3 validation nodes" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "Node0",
        last_public_key: "Node0",
        authorized?: true,
        ready?: true,
        available?: true,
        geo_patch: "AAA"
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "Node1",
        last_public_key: "Node1",
        authorized?: true,
        ready?: true,
        available?: true,
        geo_patch: "CCC"
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "Node2",
        last_public_key: "Node2",
        authorized?: true,
        ready?: true,
        available?: true,
        geo_patch: "CCC"
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "Node3",
        last_public_key: "Node3",
        authorized?: true,
        ready?: true,
        available?: true,
        geo_patch: "F24"
      })

      assert [
               %Node{geo_patch: "AAA"},
               %Node{geo_patch: "CCC"},
               %Node{geo_patch: "F24"}
             ] =
               Election.validation_nodes(
                 Transaction.new(:transfer, %TransactionData{}, "seed", 0)
               )
    end
  end

  describe "storage_nodes/1" do
    test "should return available ready nodes" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "Node0",
        last_public_key: "Node0",
        authorized?: true,
        ready?: true,
        available?: true,
        geo_patch: "AAA"
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "Node1",
        last_public_key: "Node1",
        authorized?: false,
        ready?: false,
        available?: true,
        geo_patch: "CCC"
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "Node2",
        last_public_key: "Node2",
        authorized?: false,
        ready?: true,
        available?: true,
        geo_patch: "BBB"
      })

      assert [%Node{first_public_key: "Node0"}, %Node{first_public_key: "Node2"}] =
               Election.storage_nodes(:crypto.strong_rand_bytes(32))
    end
  end
end
