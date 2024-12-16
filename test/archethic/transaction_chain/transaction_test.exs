defmodule Archethic.TransactionChain.TransactionTest do
  @moduledoc false
  use ArchethicCase, async: false

  import ArchethicCase

  alias Archethic.Crypto
  alias Archethic.Reward.MemTables.RewardTokens
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger

  alias Archethic.TransactionFactory

  doctest Archethic.TransactionChain.Transaction

  setup do
    start_supervised!(RewardTokens)
    :ok
  end

  describe "new/2" do
    test "with type ':node' create a new transaction using the node keys" do
      tx = Transaction.new(:node, %TransactionData{})

      assert tx.address == Crypto.derive_address(Crypto.next_node_public_key())
      assert tx.previous_public_key == Crypto.last_node_public_key()

      assert Crypto.verify?(
               tx.origin_signature,
               tx
               |> Transaction.extract_for_origin_signature()
               |> Transaction.serialize(:extended),
               Crypto.origin_node_public_key()
             )
    end

    test "with type ':node_shared_secrets' create a new transaction using the node shared secrets keys" do
      tx = Transaction.new(:node_shared_secrets, %TransactionData{})

      assert tx.address ==
               Crypto.derive_address(
                 Crypto.node_shared_secrets_public_key(
                   Crypto.number_of_node_shared_secrets_keys() + 1
                 )
               )

      key_index = Crypto.number_of_node_shared_secrets_keys()
      assert tx.previous_public_key == Crypto.node_shared_secrets_public_key(key_index)

      assert Crypto.verify?(
               tx.origin_signature,
               tx
               |> Transaction.extract_for_origin_signature()
               |> Transaction.serialize(:extended),
               Crypto.origin_node_public_key()
             )
    end
  end

  describe "new/4" do
    test "should create transaction with specific seed and index" do
      tx = Transaction.new(:node, %TransactionData{}, "seed", 0)
      tx2 = Transaction.new(:node, %TransactionData{}, "seed", 1)

      assert Crypto.derive_address(tx2.previous_public_key) == tx.address
    end
  end

  describe "valid_stamps_signature?/2" do
    test "should return false if validation stamp signature is invalid" do
      tx = TransactionFactory.create_transaction_with_invalid_validation_stamp_signature()

      keys = [[Crypto.first_node_public_key()]]

      refute Transaction.valid_stamps_signature?(tx, keys)
    end

    test "should return true if validation stamp signature is good" do
      tx = TransactionFactory.create_valid_transaction()

      keys = [[Crypto.first_node_public_key()]]

      assert Transaction.valid_stamps_signature?(tx, keys)
    end

    test "should return true if validation stamp signature is good having a list of public keys" do
      tx = TransactionFactory.create_valid_transaction()

      keys = [
        [random_public_key(), Crypto.first_node_public_key()],
        [random_public_key(), random_public_key()]
      ]

      assert Transaction.valid_stamps_signature?(tx, keys)
    end

    test "should return false if multiple cross validation stamps are from the same node" do
      tx = TransactionFactory.create_valid_transaction()
      cross_stamps = tx.cross_validation_stamps

      tx = %Transaction{tx | cross_validation_stamps: cross_stamps ++ cross_stamps}

      keys = [[Crypto.first_node_public_key()]]

      refute Transaction.valid_stamps_signature?(tx, keys)
    end

    test "should return false if cross validation stamps are invalid" do
      tx = TransactionFactory.create_valid_transaction()

      cross_stamps =
        tx.cross_validation_stamps
        |> Enum.map(fn cross_stamp ->
          %{cross_stamp | signature: :crypto.strong_rand_bytes(32)}
        end)

      tx = %Transaction{tx | cross_validation_stamps: cross_stamps}

      keys = [[Crypto.first_node_public_key()]]

      refute Transaction.valid_stamps_signature?(tx, keys)
    end
  end

  describe "get_movements/1 ledgers" do
    test "should return the ledgers" do
      assert [
               %TransactionMovement{
                 to: "@Alice1",
                 amount: 10,
                 type: :UCO
               },
               %TransactionMovement{
                 to: "@Alice1",
                 amount: 3,
                 type: {:token, "@BobToken", 0}
               }
             ] =
               Transaction.get_movements(%Transaction{
                 data: %TransactionData{
                   ledger: %Ledger{
                     uco: %UCOLedger{
                       transfers: [
                         %UCOLedger.Transfer{to: "@Alice1", amount: 10}
                       ]
                     },
                     token: %TokenLedger{
                       transfers: [
                         %TokenLedger.Transfer{
                           to: "@Alice1",
                           amount: 3,
                           token_address: "@BobToken",
                           token_id: 0
                         }
                       ]
                     }
                   }
                 }
               })
    end

    test "should behave properly when there is multiple times the same from" do
      alice_address = random_address()
      token_address = random_address()

      assert [
               %TransactionMovement{
                 to: ^alice_address,
                 amount: 10,
                 type: :UCO
               },
               %TransactionMovement{
                 to: ^alice_address,
                 amount: 20,
                 type: :UCO
               },
               %TransactionMovement{
                 to: ^alice_address,
                 amount: 30,
                 type: :UCO
               },
               %TransactionMovement{
                 to: ^alice_address,
                 amount: 1,
                 type: {:token, ^token_address, 0}
               },
               %TransactionMovement{
                 to: ^alice_address,
                 amount: 2,
                 type: {:token, ^token_address, 0}
               },
               %TransactionMovement{
                 to: ^alice_address,
                 amount: 3,
                 type: {:token, ^token_address, 0}
               }
             ] =
               Transaction.get_movements(%Transaction{
                 data: %TransactionData{
                   ledger: %Ledger{
                     uco: %UCOLedger{
                       transfers: [
                         %UCOLedger.Transfer{to: alice_address, amount: 10},
                         %UCOLedger.Transfer{to: alice_address, amount: 20},
                         %UCOLedger.Transfer{to: alice_address, amount: 30}
                       ]
                     },
                     token: %TokenLedger{
                       transfers: [
                         %TokenLedger.Transfer{
                           to: alice_address,
                           amount: 1,
                           token_address: token_address,
                           token_id: 0
                         },
                         %TokenLedger.Transfer{
                           to: alice_address,
                           amount: 2,
                           token_address: token_address,
                           token_id: 0
                         },
                         %TokenLedger.Transfer{
                           to: alice_address,
                           amount: 3,
                           token_address: token_address,
                           token_id: 0
                         }
                       ]
                     }
                   }
                 }
               })
    end
  end

  describe "get_movements/1 token resupply transaction" do
    test "should return the movements for a fungible token" do
      recipient1 = random_address()
      recipient1_hex = recipient1 |> Base.encode16()
      recipient2 = random_address()
      recipient2_hex = recipient2 |> Base.encode16()
      token = random_address()
      token_hex = token |> Base.encode16()

      assert [
               %TransactionMovement{
                 to: ^recipient1,
                 amount: 1_000,
                 type: {:token, ^token, 0}
               },
               %TransactionMovement{
                 to: ^recipient2,
                 amount: 2_000,
                 type: {:token, ^token, 0}
               }
             ] =
               Transaction.get_movements(
                 TransactionFactory.create_valid_transaction([],
                   type: :token,
                   content: """
                   {
                     "token_reference": "#{token_hex}",
                     "supply": 1000000,
                     "recipients": [{
                       "to": "#{recipient1_hex}",
                       "amount": 1000
                     },
                     {
                      "to": "#{recipient2_hex}",
                      "amount": 2000
                     }]
                   }
                   """
                 )
               )
    end

    test "should return an empty list if no recipients" do
      token = random_address()
      token_hex = token |> Base.encode16()

      assert [] =
               Transaction.get_movements(
                 TransactionFactory.create_valid_transaction([],
                   type: :token,
                   content: """
                   {
                     "token_reference": "#{token_hex}",
                     "supply": 1000000
                   }
                   """
                 )
               )
    end

    test "should return an empty list if invalid transaction" do
      token = random_address()
      token_hex = token |> Base.encode16()
      recipient1 = random_address()
      recipient1_hex = recipient1 |> Base.encode16()

      assert [] =
               Transaction.get_movements(
                 TransactionFactory.create_valid_transaction([],
                   type: :token,
                   content: """
                   {
                    "token_reference": "#{token_hex}"
                   }
                   """
                 )
               )

      assert [] =
               Transaction.get_movements(
                 TransactionFactory.create_valid_transaction([],
                   type: :token,
                   content: """
                   {
                    "token_reference": "not an hexadecimal",
                    "supply": 100000000,
                    "recipients": [{
                      "to": "#{recipient1_hex}",
                      "amount": 1000
                    }]
                   }
                   """
                 )
               )

      assert [] =
               Transaction.get_movements(
                 TransactionFactory.create_valid_transaction([],
                   type: :token,
                   content: """
                   {
                     "supply": 1000000
                   }
                   """
                 )
               )
    end
  end

  describe "get_movements/1 token creation transaction" do
    test "should return the movements for a fungible token" do
      recipient1 = random_address()
      recipient1_hex = recipient1 |> Base.encode16()
      recipient2 = random_address()
      recipient2_hex = recipient2 |> Base.encode16()

      tx =
        TransactionFactory.create_valid_transaction([],
          type: :token,
          content: """
          {
           "aeip": [2, 8, 19],
           "supply": 300000000,
           "type": "fungible",
           "name": "My token",
           "symbol": "MTK",
           "properties": {},
           "recipients": [{
              "to": "#{recipient1_hex}",
              "amount": 1000
            },
            {
             "to": "#{recipient2_hex}",
             "amount": 2000
            }]
          }
          """
        )

      tx_address = tx.address

      assert [
               %TransactionMovement{
                 to: ^recipient1,
                 amount: 1_000,
                 type: {:token, ^tx_address, 0}
               },
               %TransactionMovement{
                 to: ^recipient2,
                 amount: 2_000,
                 type: {:token, ^tx_address, 0}
               }
             ] = Transaction.get_movements(tx)
    end

    test "should return the movements for a non-fungible token" do
      recipient1 = random_address()
      recipient1_hex = recipient1 |> Base.encode16()

      tx =
        TransactionFactory.create_valid_transaction([],
          type: :token,
          content: """
          {
            "supply": 100000000,
            "type": "non-fungible",
            "name": "My NFT",
            "symbol": "MNFT",
            "recipients": [{
              "to": "#{recipient1_hex}",
              "amount": 100000000,
              "token_id": 1
            }]
          }
          """
        )

      tx_address = tx.address

      assert [
               %TransactionMovement{
                 to: ^recipient1,
                 amount: 100_000_000,
                 type: {:token, ^tx_address, 1}
               }
             ] = Transaction.get_movements(tx)
    end

    test "should return the movements for a non-fungible token (collection)" do
      recipient1 = random_address()
      recipient1_hex = recipient1 |> Base.encode16()

      tx =
        TransactionFactory.create_valid_transaction([],
          type: :token,
          content: """
          {
            "supply": 300000000,
            "name": "My NFT",
            "type": "non-fungible",
            "symbol": "MNFT",
            "properties": {
               "description": "this property is for all NFT"
            },
            "collection": [
               { "image": "link of the 1st NFT image" },
               { "image": "link of the 2nd NFT image" },
               {
                  "image": "link of the 3rd NFT image",
                  "other_property": "other value"
               }
            ],
            "recipients": [{
              "to": "#{recipient1_hex}",
              "amount": 100000000,
              "token_id": 3
            }]
          }
          """
        )

      tx_address = tx.address

      assert [
               %TransactionMovement{
                 to: ^recipient1,
                 amount: 100_000_000,
                 type: {:token, ^tx_address, 3}
               }
             ] = Transaction.get_movements(tx)
    end

    test "should return an empty list when trying to send a fraction of a non-fungible" do
      recipient1 = random_address()
      recipient1_hex = recipient1 |> Base.encode16()

      tx =
        TransactionFactory.create_valid_transaction([],
          type: :token,
          content: """
          {
            "supply": 100000000,
            "type": "non-fungible",
            "name": "My NFT",
            "symbol": "MNFT",
            "recipients": [{
              "to": "#{recipient1_hex}",
              "amount": 1
            }]
          }
          """
        )

      assert [] = Transaction.get_movements(tx)
    end
  end

  describe "symmetric serialization" do
    test "should support latest version" do
      tx = %Transaction{
        address:
          <<0, 0, 120, 135, 125, 48, 92, 13, 27, 60, 42, 84, 221, 204, 42, 196, 25, 37, 237, 215,
            122, 113, 54, 59, 9, 251, 27, 179, 5, 44, 116, 217, 180, 32>>,
        cross_validation_stamps: [],
        data: %Archethic.TransactionChain.TransactionData{
          code: "",
          content:
            <<0, 98, 12, 24, 6, 0, 0, 0, 1, 0, 0, 238, 143, 251, 13, 151, 68, 48, 247, 25, 179,
              245, 118, 171, 203, 76, 243, 214, 84, 147, 214, 174, 206, 214, 92, 218, 100, 225,
              114, 163, 26, 223, 186, 0, 0, 1, 126, 255, 61, 177, 215, 1, 0, 1, 0, 234, 193, 62,
              27, 61, 132, 121, 178, 119, 20, 124, 88, 206, 36, 125, 163, 108, 229, 219, 181, 143,
              253, 246, 237, 238, 21, 79, 9, 230, 172, 0, 95, 0, 0, 0, 0, 0>>,
          ledger: %Archethic.TransactionChain.TransactionData.Ledger{
            token: %Archethic.TransactionChain.TransactionData.TokenLedger{transfers: []},
            uco: %Archethic.TransactionChain.TransactionData.UCOLedger{transfers: []}
          },
          ownerships: [],
          recipients: []
        },
        origin_signature:
          <<163, 184, 57, 242, 100, 203, 42, 179, 241, 235, 35, 167, 197, 56, 228, 120, 110, 122,
            64, 31, 230, 231, 110, 247, 119, 139, 211, 85, 134, 192, 125, 6, 190, 51, 118, 60,
            239, 190, 15, 138, 6, 137, 87, 32, 13, 241, 26, 186, 1, 113, 112, 58, 24, 242, 140,
            245, 201, 66, 132, 213, 105, 229, 14, 2>>,
        previous_public_key:
          <<0, 0, 84, 200, 174, 114, 81, 219, 237, 219, 237, 222, 27, 55, 149, 8, 235, 248, 37,
            69, 1, 8, 128, 139, 184, 80, 114, 82, 40, 61, 25, 169, 26, 69>>,
        previous_signature:
          <<83, 137, 109, 48, 131, 81, 37, 65, 81, 210, 9, 87, 246, 107, 10, 101, 24, 218, 230,
            38, 212, 35, 242, 216, 223, 83, 224, 11, 168, 158, 5, 198, 202, 48, 233, 171, 107,
            127, 70, 206, 98, 145, 93, 119, 98, 58, 79, 206, 161, 21, 251, 218, 6, 44, 55, 133,
            13, 122, 125, 219, 122, 131, 73, 6>>,
        type: :oracle,
        validation_stamp: %Archethic.TransactionChain.Transaction.ValidationStamp{
          genesis_address: random_address(),
          ledger_operations:
            %Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations{
              fee: 0,
              transaction_movements: [],
              unspent_outputs: [],
              consumed_inputs: []
            },
          proof_of_election:
            <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
              0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
              0, 0, 0, 0, 0, 0, 0, 0>>,
          proof_of_integrity:
            <<0, 188, 101, 205, 214, 203, 136, 90, 130, 68, 147, 79, 76, 46, 139, 19, 189, 123,
              142, 29, 113, 208, 111, 136, 227, 252, 213, 180, 80, 70, 158, 27, 148>>,
          proof_of_work:
            <<0, 0, 29, 150, 125, 113, 178, 225, 53, 200, 66, 6, 221, 209, 8, 181, 146, 90, 44,
              217, 156, 142, 188, 90, 181, 216, 253, 46, 201, 64, 12, 227, 201, 138>>,
          recipients: [],
          signature:
            <<187, 93, 5, 6, 190, 102, 244, 88, 141, 142, 7, 138, 178, 77, 128, 21, 95, 29, 222,
              145, 211, 18, 48, 16, 185, 69, 209, 146, 56, 26, 106, 191, 101, 56, 15, 99, 52, 179,
              212, 169, 7, 30, 131, 39, 100, 115, 73, 176, 212, 121, 236, 91, 94, 118, 108, 9,
              228, 44, 237, 157, 90, 243, 90, 6>>,
          timestamp: ~U[2022-02-15 21:15:50.000Z],
          protocol_version: current_protocol_version()
        },
        version: current_transaction_version()
      }

      assert tx ==
               tx
               |> Transaction.serialize()
               |> Transaction.deserialize()
               |> elem(0)
    end
  end
end
