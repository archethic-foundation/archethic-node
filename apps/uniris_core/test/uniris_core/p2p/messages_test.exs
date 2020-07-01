defmodule UnirisCore.P2P.MessageTest do
  use UnirisCoreCase

  alias UnirisCore.P2P.Message
  alias UnirisCore.P2P.Message.GetBootstrappingNodes
  alias UnirisCore.P2P.Message.GetStorageNonce
  alias UnirisCore.P2P.Message.ListNodes
  alias UnirisCore.P2P.Message.NewTransaction
  alias UnirisCore.P2P.Message.GetTransaction
  alias UnirisCore.P2P.Message.GetTransactionChain
  alias UnirisCore.P2P.Message.GetUnspentOutputs
  alias UnirisCore.P2P.Message.GetProofOfIntegrity
  alias UnirisCore.P2P.Message.StartMining
  alias UnirisCore.P2P.Message.GetTransactionHistory
  alias UnirisCore.P2P.Message.AddContext
  alias UnirisCore.P2P.Message.CrossValidate
  alias UnirisCore.P2P.Message.CrossValidationDone
  alias UnirisCore.P2P.Message.ReplicateTransaction
  alias UnirisCore.P2P.Message.AcknowledgeStorage
  alias UnirisCore.P2P.Message.GetBeaconSlots
  alias UnirisCore.P2P.Message.AddNodeInfo
  alias UnirisCore.P2P.Message.GetLastTransaction
  alias UnirisCore.P2P.Message.GetBalance
  alias UnirisCore.P2P.Message.GetTransactionInputs
  alias UnirisCore.P2P.Message.BootstrappingNodes
  alias UnirisCore.P2P.Message.EncryptedStorageNonce
  alias UnirisCore.P2P.Message.TransactionHistory
  alias UnirisCore.P2P.Message.Balance
  alias UnirisCore.P2P.Message.NodeList
  alias UnirisCore.P2P.Message.BeaconSlotList
  alias UnirisCore.P2P.Message.UnspentOutputList
  alias UnirisCore.P2P.Message.TransactionList
  alias UnirisCore.P2P.Message.Ok
  alias UnirisCore.P2P.Message.NotFound
  alias UnirisCore.P2P.Message.ProofOfIntegrity

  alias UnirisCore.Crypto
  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations.NodeMovement
  alias UnirisCore.Transaction.CrossValidationStamp
  alias UnirisCore.P2P.Node
  alias UnirisCore.BeaconSlot
  alias UnirisCore.BeaconSlot.TransactionInfo
  alias UnirisCore.BeaconSlot.NodeInfo

  doctest Message

  describe "encode/1" do
    test "should serialize a GetBootstrappingNodes message" do
      assert <<0::8, "AAA">> = Message.encode(%GetBootstrappingNodes{patch: "AAA"})
    end

    test "should serialize a GetStorageNonce message" do
      {public_key, _} = Crypto.generate_deterministic_keypair("seed", :secp256r1)

      assert <<1::8, public_key::binary-size(66)>> ==
               Message.encode(%GetStorageNonce{public_key: public_key})

      {public_key, _} = Crypto.generate_deterministic_keypair("seed", :ed25519)

      assert <<1::8, public_key::binary-size(33)>> ==
               Message.encode(%GetStorageNonce{public_key: public_key})
    end

    test "should serialize a ListNodes message" do
      assert <<2::8>> = Message.encode(%ListNodes{})
    end

    test "should serialize a GetTransaction message" do
      address = :crypto.strong_rand_bytes(33)
      assert <<3::8, address::binary>> == Message.encode(%GetTransaction{address: address})
    end

    test "should serialize a GetTransactionChain message" do
      address = :crypto.strong_rand_bytes(33)
      assert <<4::8, address::binary>> == Message.encode(%GetTransactionChain{address: address})
    end

    test "should serialize a GetUnspentOutputs message" do
      address = :crypto.strong_rand_bytes(33)
      assert <<5::8, address::binary>> == Message.encode(%GetUnspentOutputs{address: address})
    end

    test "should serialize a GetProofOfIntegrity message" do
      address = :crypto.strong_rand_bytes(33)
      assert <<6::8, address::binary>> == Message.encode(%GetProofOfIntegrity{address: address})
    end

    test "should serialize a NewTransaction message" do
      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      tx_bin = Transaction.serialize(tx)
      assert <<7::8, tx_bin::binary>> == Message.encode(%NewTransaction{transaction: tx})
    end

    test "should serialize a StartMining message" do
      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)
      {welcome_node_public_key, _} = Crypto.generate_deterministic_keypair("wkey")

      validation_node_public_keys =
        Enum.map(1..10, fn i ->
          {pub, _} = Crypto.generate_deterministic_keypair("vkey" <> Integer.to_string(i))
          pub
        end)

      assert <<8::8, Transaction.serialize(tx)::binary, welcome_node_public_key::binary, 10::8,
               :erlang.list_to_binary(validation_node_public_keys)::binary>> ==
               Message.encode(%StartMining{
                 transaction: tx,
                 welcome_node_public_key: welcome_node_public_key,
                 validation_node_public_keys: validation_node_public_keys
               })
    end

    test "should serialize a GetTransactionHistory message" do
      address = :crypto.strong_rand_bytes(33)

      assert <<9::8, _::binary-size(33)>> =
               Message.encode(%GetTransactionHistory{address: address})
    end

    test "should serialize a AddContext message" do
      msg = %AddContext{
        address:
          <<0, 227, 129, 244, 35, 48, 113, 14, 75, 1, 127, 107, 32, 29, 93, 232, 119, 254, 1, 65,
            32, 47, 129, 164, 142, 240, 43, 22, 81, 188, 212, 56, 238>>,
        validation_node_public_key:
          <<0, 92, 208, 222, 119, 27, 128, 82, 69, 163, 128, 196, 105, 19, 18, 99, 217, 105, 80,
            238, 155, 239, 91, 54, 82, 200, 16, 121, 32, 83, 63, 79, 88>>,
        context: %UnirisCore.Mining.Context{
          involved_nodes: [
            <<0, 22, 38, 34, 13, 213, 91, 210, 214, 66, 148, 122, 220, 63, 176, 232, 205, 35, 153,
              176, 223, 178, 72, 88, 6, 41, 167, 163, 205, 98, 172, 249, 141>>
          ],
          cross_validation_nodes_view: <<1::1, 1::1, 0::1, 1::1>>,
          chain_storage_nodes_view: <<1::1, 0::1, 0::1, 1::1, 0::1>>,
          beacon_storage_nodes_view: <<0::1, 1::1, 1::1, 1::1>>
        }
      }

      assert <<10::8, 0, 227, 129, 244, 35, 48, 113, 14, 75, 1, 127, 107, 32, 29, 93, 232, 119,
               254, 1, 65, 32, 47, 129, 164, 142, 240, 43, 22, 81, 188, 212, 56, 238, 0, 92, 208,
               222, 119, 27, 128, 82, 69, 163, 128, 196, 105, 19, 18, 99, 217, 105, 80, 238, 155,
               239, 91, 54, 82, 200, 16, 121, 32, 83, 63, 79, 88, 1, 0, 22, 38, 34, 13, 213, 91,
               210, 214, 66, 148, 122, 220, 63, 176, 232, 205, 35, 153, 176, 223, 178, 72, 88, 6,
               41, 167, 163, 205, 98, 172, 249, 141, 4, 1::1, 1::1, 0::1, 1::1, 5, 1::1, 0::1,
               0::1, 1::1, 0::1, 4, 0::1, 1::1, 1::1, 1::1>> == Message.encode(msg)
    end

    test "should serialize a CrossValidate message" do
      msg = %CrossValidate{
        address:
          <<0, 227, 129, 244, 35, 48, 113, 14, 75, 1, 127, 107, 32, 29, 93, 232, 119, 254, 1, 65,
            32, 47, 129, 164, 142, 240, 43, 22, 81, 188, 212, 56, 238>>,
        validation_stamp: %ValidationStamp{
          proof_of_work:
            <<0, 206, 159, 122, 114, 106, 65, 116, 18, 224, 214, 2, 26, 213, 36, 82, 175, 176,
              180, 191, 255, 46, 113, 134, 227, 253, 189, 81, 16, 97, 33, 114, 85>>,
          proof_of_integrity:
            <<0, 63, 70, 80, 109, 148, 124, 179, 105, 198, 92, 39, 212, 240, 48, 96, 69, 244, 213,
              246, 75, 82, 83, 170, 121, 42, 105, 30, 23, 3, 231, 178, 153>>,
          ledger_operations: %LedgerOperations{
            fee: 0.01,
            transaction_movements: [],
            node_movements: [
              %NodeMovement{
                to:
                  <<0, 92, 208, 222, 119, 27, 128, 82, 69, 163, 128, 196, 105, 19, 18, 99, 217,
                    105, 80, 238, 155, 239, 91, 54, 82, 200, 16, 121, 32, 83, 63, 79, 88>>,
                amount: 0.01
              }
            ],
            unspent_outputs: []
          },
          signature:
            <<231, 4, 252, 234, 6, 126, 91, 87, 41, 70, 76, 220, 116, 238, 128, 189, 94, 124, 207,
              90, 32, 143, 239, 153, 101, 148, 189, 125, 25, 235, 20, 207, 168, 10, 86, 59, 14,
              249, 104, 144, 141, 151, 232, 149, 24, 189, 225, 56, 65, 208, 220, 202, 169, 166,
              36, 248, 98, 108, 241, 114, 47, 102, 176, 212>>
        },
        replication_tree: [<<1::1, 0::1, 1::1>>, <<0::1, 1::1, 0::1>>, <<1::1, 0::1, 0::1>>]
      }

      assert <<11::8, 0, 227, 129, 244, 35, 48, 113, 14, 75, 1, 127, 107, 32, 29, 93, 232, 119,
               254, 1, 65, 32, 47, 129, 164, 142, 240, 43, 22, 81, 188, 212, 56, 238, 0, 206, 159,
               122, 114, 106, 65, 116, 18, 224, 214, 2, 26, 213, 36, 82, 175, 176, 180, 191, 255,
               46, 113, 134, 227, 253, 189, 81, 16, 97, 33, 114, 85, 0, 63, 70, 80, 109, 148, 124,
               179, 105, 198, 92, 39, 212, 240, 48, 96, 69, 244, 213, 246, 75, 82, 83, 170, 121,
               42, 105, 30, 23, 3, 231, 178, 153, 63, 132, 122, 225, 71, 174, 20, 123, 0, 1, 0,
               92, 208, 222, 119, 27, 128, 82, 69, 163, 128, 196, 105, 19, 18, 99, 217, 105, 80,
               238, 155, 239, 91, 54, 82, 200, 16, 121, 32, 83, 63, 79, 88, 63, 132, 122, 225, 71,
               174, 20, 123, 0, 64, 231, 4, 252, 234, 6, 126, 91, 87, 41, 70, 76, 220, 116, 238,
               128, 189, 94, 124, 207, 90, 32, 143, 239, 153, 101, 148, 189, 125, 25, 235, 20,
               207, 168, 10, 86, 59, 14, 249, 104, 144, 141, 151, 232, 149, 24, 189, 225, 56, 65,
               208, 220, 202, 169, 166, 36, 248, 98, 108, 241, 114, 47, 102, 176, 212, 3, 3, 1::1,
               0::1, 1::1, 0::1, 1::1, 0::1, 1::1, 0::1, 0::1>> = Message.encode(msg)
    end

    test "should serialize a CrossValidationDone message" do
      msg = %CrossValidationDone{
        address:
          <<0, 227, 129, 244, 35, 48, 113, 14, 75, 1, 127, 107, 32, 29, 93, 232, 119, 254, 1, 65,
            32, 47, 129, 164, 142, 240, 43, 22, 81, 188, 212, 56, 238>>,
        cross_validation_stamp: %CrossValidationStamp{
          node_public_key:
            <<0, 92, 208, 222, 119, 27, 128, 82, 69, 163, 128, 196, 105, 19, 18, 99, 217, 105, 80,
              238, 155, 239, 91, 54, 82, 200, 16, 121, 32, 83, 63, 79, 88>>,
          signature:
            <<231, 4, 252, 234, 6, 126, 91, 87, 41, 70, 76, 220, 116, 238, 128, 189, 94, 124, 207,
              90, 32, 143, 239, 153, 101, 148, 189, 125, 25, 235, 20, 207, 168, 10, 86, 59, 14,
              249, 104, 144, 141, 151, 232, 149, 24, 189, 225, 56, 65, 208, 220, 202, 169, 166,
              36, 248, 98, 108, 241, 114, 47, 102, 176, 212>>,
          inconsistencies: []
        }
      }

      <<12::8, 0, 227, 129, 244, 35, 48, 113, 14, 75, 1, 127, 107, 32, 29, 93, 232, 119, 254, 1,
        65, 32, 47, 129, 164, 142, 240, 43, 22, 81, 188, 212, 56, 238, 0, 92, 208, 222, 119, 27,
        128, 82, 69, 163, 128, 196, 105, 19, 18, 99, 217, 105, 80, 238, 155, 239, 91, 54, 82, 200,
        16, 121, 32, 83, 63, 79, 88, 64, 231, 4, 252, 234, 6, 126, 91, 87, 41, 70, 76, 220, 116,
        238, 128, 189, 94, 124, 207, 90, 32, 143, 239, 153, 101, 148, 189, 125, 25, 235, 20, 207,
        168, 10, 86, 59, 14, 249, 104, 144, 141, 151, 232, 149, 24, 189, 225, 56, 65, 208, 220,
        202, 169, 166, 36, 248, 98, 108, 241, 114, 47, 102, 176, 212, 0>> = Message.encode(msg)
    end

    test "should serialize a ReplicateTransaction message" do
      msg = %ReplicateTransaction{
        transaction: %Transaction{
          address:
            <<0, 46, 140, 65, 49, 7, 111, 10, 130, 53, 72, 25, 43, 47, 81, 130, 161, 225, 87, 144,
              186, 117, 170, 105, 205, 173, 102, 49, 176, 8, 45, 49, 82>>,
          type: :transfer,
          timestamp: ~U[2020-06-26 06:37:04Z],
          data: %TransactionData{},
          previous_public_key:
            <<0, 221, 122, 240, 119, 132, 26, 237, 200, 88, 209, 23, 240, 176, 190, 89, 67, 120,
              61, 106, 117, 10, 14, 12, 177, 171, 237, 66, 113, 45, 18, 195, 249>>,
          previous_signature:
            <<206, 119, 19, 59, 13, 255, 98, 28, 80, 65, 115, 97, 216, 28, 51, 237, 180, 94, 197,
              228, 50, 240, 155, 61, 242, 17, 172, 225, 223, 8, 104, 220, 195, 33, 46, 185, 88,
              223, 224, 105, 41, 107, 67, 6, 92, 78, 15, 142, 47, 192, 214, 66, 124, 30, 228, 167,
              96, 61, 68, 188, 152, 246, 42, 246>>,
          origin_signature:
            <<238, 102, 94, 142, 31, 243, 44, 162, 254, 161, 177, 121, 166, 204, 152, 126, 66,
              207, 0, 75, 174, 126, 64, 226, 155, 92, 71, 152, 119, 80, 150, 119, 88, 40, 110,
              175, 135, 180, 179, 28, 57, 84, 35, 156, 173, 212, 235, 155, 226, 41, 148, 171, 132,
              196, 120, 51, 136, 4, 78, 123, 70, 44, 76, 162>>,
          validation_stamp: %ValidationStamp{
            proof_of_work:
              <<0, 206, 159, 122, 114, 106, 65, 116, 18, 224, 214, 2, 26, 213, 36, 82, 175, 176,
                180, 191, 255, 46, 113, 134, 227, 253, 189, 81, 16, 97, 33, 114, 85>>,
            proof_of_integrity:
              <<0, 63, 70, 80, 109, 148, 124, 179, 105, 198, 92, 39, 212, 240, 48, 96, 69, 244,
                213, 246, 75, 82, 83, 170, 121, 42, 105, 30, 23, 3, 231, 178, 153>>,
            ledger_operations: %LedgerOperations{
              fee: 0.01,
              transaction_movements: [],
              node_movements: [
                %NodeMovement{
                  to:
                    <<0, 92, 208, 222, 119, 27, 128, 82, 69, 163, 128, 196, 105, 19, 18, 99, 217,
                      105, 80, 238, 155, 239, 91, 54, 82, 200, 16, 121, 32, 83, 63, 79, 88>>,
                  amount: 0.01
                }
              ],
              unspent_outputs: []
            },
            signature:
              <<231, 4, 252, 234, 6, 126, 91, 87, 41, 70, 76, 220, 116, 238, 128, 189, 94, 124,
                207, 90, 32, 143, 239, 153, 101, 148, 189, 125, 25, 235, 20, 207, 168, 10, 86, 59,
                14, 249, 104, 144, 141, 151, 232, 149, 24, 189, 225, 56, 65, 208, 220, 202, 169,
                166, 36, 248, 98, 108, 241, 114, 47, 102, 176, 212>>
          },
          cross_validation_stamps: [
            %CrossValidationStamp{
              node_public_key:
                <<0, 161, 146, 84, 231, 250, 25, 216, 247, 158, 26, 32, 219, 6, 128, 253, 127,
                  119, 121, 206, 58, 142, 140, 194, 61, 235, 224, 193, 56, 82, 253, 19, 131>>,
              signature:
                <<44, 66, 52, 214, 59, 145, 63, 7, 237, 115, 10, 255, 237, 85, 175, 115, 177, 85,
                  20, 76, 108, 118, 141, 190, 6, 84, 28, 134, 37, 235, 114, 30, 169, 151, 124,
                  242, 58, 26, 146, 125, 89, 64, 181, 253, 58, 199, 73, 12, 237, 134, 93, 73, 157,
                  123, 248, 199, 252, 138, 202, 227, 69, 83, 11, 29>>,
              inconsistencies: []
            }
          ]
        }
      }

      assert <<13::8, 0, 46, 140, 65, 49, 7, 111, 10, 130, 53, 72, 25, 43, 47, 81, 130, 161, 225,
               87, 144, 186, 117, 170, 105, 205, 173, 102, 49, 176, 8, 45, 49, 82, 2, 94, 245,
               151, 144, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 221, 122, 240, 119, 132,
               26, 237, 200, 88, 209, 23, 240, 176, 190, 89, 67, 120, 61, 106, 117, 10, 14, 12,
               177, 171, 237, 66, 113, 45, 18, 195, 249, 64, 206, 119, 19, 59, 13, 255, 98, 28,
               80, 65, 115, 97, 216, 28, 51, 237, 180, 94, 197, 228, 50, 240, 155, 61, 242, 17,
               172, 225, 223, 8, 104, 220, 195, 33, 46, 185, 88, 223, 224, 105, 41, 107, 67, 6,
               92, 78, 15, 142, 47, 192, 214, 66, 124, 30, 228, 167, 96, 61, 68, 188, 152, 246,
               42, 246, 64, 238, 102, 94, 142, 31, 243, 44, 162, 254, 161, 177, 121, 166, 204,
               152, 126, 66, 207, 0, 75, 174, 126, 64, 226, 155, 92, 71, 152, 119, 80, 150, 119,
               88, 40, 110, 175, 135, 180, 179, 28, 57, 84, 35, 156, 173, 212, 235, 155, 226, 41,
               148, 171, 132, 196, 120, 51, 136, 4, 78, 123, 70, 44, 76, 162, 1, 0, 206, 159, 122,
               114, 106, 65, 116, 18, 224, 214, 2, 26, 213, 36, 82, 175, 176, 180, 191, 255, 46,
               113, 134, 227, 253, 189, 81, 16, 97, 33, 114, 85, 0, 63, 70, 80, 109, 148, 124,
               179, 105, 198, 92, 39, 212, 240, 48, 96, 69, 244, 213, 246, 75, 82, 83, 170, 121,
               42, 105, 30, 23, 3, 231, 178, 153, 63, 132, 122, 225, 71, 174, 20, 123, 0, 1, 0,
               92, 208, 222, 119, 27, 128, 82, 69, 163, 128, 196, 105, 19, 18, 99, 217, 105, 80,
               238, 155, 239, 91, 54, 82, 200, 16, 121, 32, 83, 63, 79, 88, 63, 132, 122, 225, 71,
               174, 20, 123, 0, 64, 231, 4, 252, 234, 6, 126, 91, 87, 41, 70, 76, 220, 116, 238,
               128, 189, 94, 124, 207, 90, 32, 143, 239, 153, 101, 148, 189, 125, 25, 235, 20,
               207, 168, 10, 86, 59, 14, 249, 104, 144, 141, 151, 232, 149, 24, 189, 225, 56, 65,
               208, 220, 202, 169, 166, 36, 248, 98, 108, 241, 114, 47, 102, 176, 212, 1, 0, 161,
               146, 84, 231, 250, 25, 216, 247, 158, 26, 32, 219, 6, 128, 253, 127, 119, 121, 206,
               58, 142, 140, 194, 61, 235, 224, 193, 56, 82, 253, 19, 131, 64, 44, 66, 52, 214,
               59, 145, 63, 7, 237, 115, 10, 255, 237, 85, 175, 115, 177, 85, 20, 76, 108, 118,
               141, 190, 6, 84, 28, 134, 37, 235, 114, 30, 169, 151, 124, 242, 58, 26, 146, 125,
               89, 64, 181, 253, 58, 199, 73, 12, 237, 134, 93, 73, 157, 123, 248, 199, 252, 138,
               202, 227, 69, 83, 11, 29, 0>> = Message.encode(msg)
    end

    test "should serialize a AcknowledgeStorage message" do
      address = :crypto.strong_rand_bytes(33)

      msg = %AcknowledgeStorage{
        address: address
      }

      <<14::8, _::binary-size(33)>> = Message.encode(msg)
    end

    test "should serialize a GetBeaconSlots message" do
      msg = %GetBeaconSlots{
        subsets_slots: %{
          "01" => [
            ~U[2020-06-25 15:11:53.57Z],
            ~U[2020-06-25 15:13:03.10Z]
          ]
        }
      }

      assert <<15::8, 1::8, "01", 2::16, 94, 244, 190, 185, 94, 244, 190, 255>> =
               Message.encode(msg)
    end

    test "should serialize a AddNodeInfo message" do
      msg = %AddNodeInfo{
        subset: <<0>>,
        node_info: %UnirisCore.BeaconSlot.NodeInfo{
          public_key:
            <<0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
              100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241>>,
          timestamp: ~U[2020-06-25 15:11:53Z],
          ready?: true
        }
      }

      assert <<16::8, 0, 0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174,
               190, 91, 100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241,
               94, 244, 190, 185, 1::1>> = Message.encode(msg)
    end

    test "should serialize a GetLastTransaction message" do
      address = :crypto.strong_rand_bytes(32)

      msg = %GetLastTransaction{
        address: address
      }

      assert <<17::8, address::binary>> == Message.encode(msg)
    end

    test "should serialize a GetBalance message" do
      address = :crypto.strong_rand_bytes(32)

      msg = %GetBalance{
        address: address
      }

      assert <<18::8, address::binary>> == Message.encode(msg)
    end

    test "should serialize a GetTransactionInputs message" do
      address = :crypto.strong_rand_bytes(32)

      msg = %GetTransactionInputs{
        address: address
      }

      assert <<19::8, address::binary>> == Message.encode(msg)
    end

    test "should serialize a Ok message" do
      msg = %Ok{}
      assert <<255>> == Message.encode(msg)
    end

    test "should serialize a NotFound message" do
      msg = %NotFound{}
      assert <<254>> == Message.encode(msg)
    end

    test "should serialize a Transaction message" do
      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)
      tx_bin = Transaction.serialize(tx)
      assert <<253, tx_bin::binary>> == Message.encode(tx)
    end

    test "should serialize a TransactionList message" do
      msg = %TransactionList{
        transactions: [
          %Transaction{
            address:
              <<0, 46, 140, 65, 49, 7, 111, 10, 130, 53, 72, 25, 43, 47, 81, 130, 161, 225, 87,
                144, 186, 117, 170, 105, 205, 173, 102, 49, 176, 8, 45, 49, 82>>,
            type: :transfer,
            timestamp: ~U[2020-06-26 06:37:04Z],
            data: %TransactionData{},
            previous_public_key:
              <<0, 221, 122, 240, 119, 132, 26, 237, 200, 88, 209, 23, 240, 176, 190, 89, 67, 120,
                61, 106, 117, 10, 14, 12, 177, 171, 237, 66, 113, 45, 18, 195, 249>>,
            previous_signature:
              <<206, 119, 19, 59, 13, 255, 98, 28, 80, 65, 115, 97, 216, 28, 51, 237, 180, 94,
                197, 228, 50, 240, 155, 61, 242, 17, 172, 225, 223, 8, 104, 220, 195, 33, 46, 185,
                88, 223, 224, 105, 41, 107, 67, 6, 92, 78, 15, 142, 47, 192, 214, 66, 124, 30,
                228, 167, 96, 61, 68, 188, 152, 246, 42, 246>>,
            origin_signature:
              <<238, 102, 94, 142, 31, 243, 44, 162, 254, 161, 177, 121, 166, 204, 152, 126, 66,
                207, 0, 75, 174, 126, 64, 226, 155, 92, 71, 152, 119, 80, 150, 119, 88, 40, 110,
                175, 135, 180, 179, 28, 57, 84, 35, 156, 173, 212, 235, 155, 226, 41, 148, 171,
                132, 196, 120, 51, 136, 4, 78, 123, 70, 44, 76, 162>>,
            validation_stamp: %ValidationStamp{
              proof_of_work:
                <<0, 206, 159, 122, 114, 106, 65, 116, 18, 224, 214, 2, 26, 213, 36, 82, 175, 176,
                  180, 191, 255, 46, 113, 134, 227, 253, 189, 81, 16, 97, 33, 114, 85>>,
              proof_of_integrity:
                <<0, 63, 70, 80, 109, 148, 124, 179, 105, 198, 92, 39, 212, 240, 48, 96, 69, 244,
                  213, 246, 75, 82, 83, 170, 121, 42, 105, 30, 23, 3, 231, 178, 153>>,
              ledger_operations: %LedgerOperations{
                fee: 0.01,
                transaction_movements: [],
                node_movements: [
                  %NodeMovement{
                    to:
                      <<0, 92, 208, 222, 119, 27, 128, 82, 69, 163, 128, 196, 105, 19, 18, 99,
                        217, 105, 80, 238, 155, 239, 91, 54, 82, 200, 16, 121, 32, 83, 63, 79,
                        88>>,
                    amount: 0.01
                  }
                ],
                unspent_outputs: []
              },
              signature:
                <<231, 4, 252, 234, 6, 126, 91, 87, 41, 70, 76, 220, 116, 238, 128, 189, 94, 124,
                  207, 90, 32, 143, 239, 153, 101, 148, 189, 125, 25, 235, 20, 207, 168, 10, 86,
                  59, 14, 249, 104, 144, 141, 151, 232, 149, 24, 189, 225, 56, 65, 208, 220, 202,
                  169, 166, 36, 248, 98, 108, 241, 114, 47, 102, 176, 212>>
            },
            cross_validation_stamps: [
              %CrossValidationStamp{
                node_public_key:
                  <<0, 161, 146, 84, 231, 250, 25, 216, 247, 158, 26, 32, 219, 6, 128, 253, 127,
                    119, 121, 206, 58, 142, 140, 194, 61, 235, 224, 193, 56, 82, 253, 19, 131>>,
                signature:
                  <<44, 66, 52, 214, 59, 145, 63, 7, 237, 115, 10, 255, 237, 85, 175, 115, 177,
                    85, 20, 76, 108, 118, 141, 190, 6, 84, 28, 134, 37, 235, 114, 30, 169, 151,
                    124, 242, 58, 26, 146, 125, 89, 64, 181, 253, 58, 199, 73, 12, 237, 134, 93,
                    73, 157, 123, 248, 199, 252, 138, 202, 227, 69, 83, 11, 29>>,
                inconsistencies: []
              }
            ]
          }
        ]
      }

      assert <<252, 1::32, 0, 46, 140, 65, 49, 7, 111, 10, 130, 53, 72, 25, 43, 47, 81, 130, 161,
               225, 87, 144, 186, 117, 170, 105, 205, 173, 102, 49, 176, 8, 45, 49, 82, 2, 94,
               245, 151, 144, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 221, 122, 240, 119,
               132, 26, 237, 200, 88, 209, 23, 240, 176, 190, 89, 67, 120, 61, 106, 117, 10, 14,
               12, 177, 171, 237, 66, 113, 45, 18, 195, 249, 64, 206, 119, 19, 59, 13, 255, 98,
               28, 80, 65, 115, 97, 216, 28, 51, 237, 180, 94, 197, 228, 50, 240, 155, 61, 242,
               17, 172, 225, 223, 8, 104, 220, 195, 33, 46, 185, 88, 223, 224, 105, 41, 107, 67,
               6, 92, 78, 15, 142, 47, 192, 214, 66, 124, 30, 228, 167, 96, 61, 68, 188, 152, 246,
               42, 246, 64, 238, 102, 94, 142, 31, 243, 44, 162, 254, 161, 177, 121, 166, 204,
               152, 126, 66, 207, 0, 75, 174, 126, 64, 226, 155, 92, 71, 152, 119, 80, 150, 119,
               88, 40, 110, 175, 135, 180, 179, 28, 57, 84, 35, 156, 173, 212, 235, 155, 226, 41,
               148, 171, 132, 196, 120, 51, 136, 4, 78, 123, 70, 44, 76, 162, 1, 0, 206, 159, 122,
               114, 106, 65, 116, 18, 224, 214, 2, 26, 213, 36, 82, 175, 176, 180, 191, 255, 46,
               113, 134, 227, 253, 189, 81, 16, 97, 33, 114, 85, 0, 63, 70, 80, 109, 148, 124,
               179, 105, 198, 92, 39, 212, 240, 48, 96, 69, 244, 213, 246, 75, 82, 83, 170, 121,
               42, 105, 30, 23, 3, 231, 178, 153, 63, 132, 122, 225, 71, 174, 20, 123, 0, 1, 0,
               92, 208, 222, 119, 27, 128, 82, 69, 163, 128, 196, 105, 19, 18, 99, 217, 105, 80,
               238, 155, 239, 91, 54, 82, 200, 16, 121, 32, 83, 63, 79, 88, 63, 132, 122, 225, 71,
               174, 20, 123, 0, 64, 231, 4, 252, 234, 6, 126, 91, 87, 41, 70, 76, 220, 116, 238,
               128, 189, 94, 124, 207, 90, 32, 143, 239, 153, 101, 148, 189, 125, 25, 235, 20,
               207, 168, 10, 86, 59, 14, 249, 104, 144, 141, 151, 232, 149, 24, 189, 225, 56, 65,
               208, 220, 202, 169, 166, 36, 248, 98, 108, 241, 114, 47, 102, 176, 212, 1, 0, 161,
               146, 84, 231, 250, 25, 216, 247, 158, 26, 32, 219, 6, 128, 253, 127, 119, 121, 206,
               58, 142, 140, 194, 61, 235, 224, 193, 56, 82, 253, 19, 131, 64, 44, 66, 52, 214,
               59, 145, 63, 7, 237, 115, 10, 255, 237, 85, 175, 115, 177, 85, 20, 76, 108, 118,
               141, 190, 6, 84, 28, 134, 37, 235, 114, 30, 169, 151, 124, 242, 58, 26, 146, 125,
               89, 64, 181, 253, 58, 199, 73, 12, 237, 134, 93, 73, 157, 123, 248, 199, 252, 138,
               202, 227, 69, 83, 11, 29, 0>> == Message.encode(msg)
    end

    test "should serialize a UnspentOutputList message " do
      msg = %UnspentOutputList{
        unspent_outputs: [
          %UnspentOutput{
            from:
              <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
                159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
            amount: 10.5
          }
        ]
      }

      assert <<251::8, 1::32, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126,
               45, 68, 194, 159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186,
               64, 37, 0, 0, 0, 0, 0, 0>> = Message.encode(msg)
    end

    test "should serialize a NodeList message" do
      msg = %NodeList{
        nodes: [
          %Node{
            ip: {127, 0, 0, 1},
            port: 3000,
            first_public_key:
              <<0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64,
                92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226>>,
            last_public_key:
              <<0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64,
                92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226>>,
            geo_patch: "FA9",
            network_patch: "AVC",
            available?: true,
            average_availability: 0.8,
            enrollment_date: ~U[2020-06-26 08:36:11Z],
            ready_date: ~U[2020-06-26 08:36:11Z],
            ready?: true,
            authorization_date: ~U[2020-06-26 08:36:11Z],
            authorized?: true
          }
        ]
      }

      assert <<250::8, 1::16, 127, 0, 0, 1, 11, 184, "FA9", "AVC", 80, 94, 245, 179, 123, 1::1,
               1::1, 94, 245, 179, 123, 1::1, 94, 245, 179, 123, 0, 182, 67, 168, 252, 227, 203,
               142, 164, 142, 248, 159, 209, 249, 247, 86, 64, 92, 224, 91, 182, 122, 49, 209,
               169, 96, 111, 219, 204, 57, 250, 59, 226, 0, 182, 67, 168, 252, 227, 203, 142, 164,
               142, 248, 159, 209, 249, 247, 86, 64, 92, 224, 91, 182, 122, 49, 209, 169, 96, 111,
               219, 204, 57, 250, 59, 226>> = Message.encode(msg)
    end

    test "should serialize a BeaconSlotList message" do
      msg = %BeaconSlotList{
        slots: [
          %BeaconSlot{
            transactions: [
              %TransactionInfo{
                address:
                  <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232,
                    166, 99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255,
                    12>>,
                timestamp: ~U[2020-06-25 15:11:53Z],
                type: :transfer,
                movements_addresses: []
              }
            ],
            nodes: [
              %NodeInfo{
                public_key:
                  <<0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190,
                    91, 100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241>>,
                timestamp: ~U[2020-06-25 15:11:53Z],
                ready?: true
              }
            ]
          }
        ]
      }

      <<249::8, 0, 1, 0, 0, 0, 1, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205,
        249, 65, 232, 166, 99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255,
        12, 94, 244, 190, 185, 2, 0, 0, 0, 1, 0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148,
        120, 31, 200, 255, 174, 190, 91, 100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140,
        87, 143, 241, 94, 244, 190, 185, 1::1>> = Message.encode(msg)
    end

    test "should serialize a TransactionHistory message" do
      msg = %TransactionHistory{
        transaction_chain: [
          %Transaction{
            address:
              <<0, 46, 140, 65, 49, 7, 111, 10, 130, 53, 72, 25, 43, 47, 81, 130, 161, 225, 87,
                144, 186, 117, 170, 105, 205, 173, 102, 49, 176, 8, 45, 49, 82>>,
            type: :transfer,
            timestamp: ~U[2020-06-26 06:37:04Z],
            data: %TransactionData{},
            previous_public_key:
              <<0, 221, 122, 240, 119, 132, 26, 237, 200, 88, 209, 23, 240, 176, 190, 89, 67, 120,
                61, 106, 117, 10, 14, 12, 177, 171, 237, 66, 113, 45, 18, 195, 249>>,
            previous_signature:
              <<206, 119, 19, 59, 13, 255, 98, 28, 80, 65, 115, 97, 216, 28, 51, 237, 180, 94,
                197, 228, 50, 240, 155, 61, 242, 17, 172, 225, 223, 8, 104, 220, 195, 33, 46, 185,
                88, 223, 224, 105, 41, 107, 67, 6, 92, 78, 15, 142, 47, 192, 214, 66, 124, 30,
                228, 167, 96, 61, 68, 188, 152, 246, 42, 246>>,
            origin_signature:
              <<238, 102, 94, 142, 31, 243, 44, 162, 254, 161, 177, 121, 166, 204, 152, 126, 66,
                207, 0, 75, 174, 126, 64, 226, 155, 92, 71, 152, 119, 80, 150, 119, 88, 40, 110,
                175, 135, 180, 179, 28, 57, 84, 35, 156, 173, 212, 235, 155, 226, 41, 148, 171,
                132, 196, 120, 51, 136, 4, 78, 123, 70, 44, 76, 162>>,
            validation_stamp: %ValidationStamp{
              proof_of_work:
                <<0, 206, 159, 122, 114, 106, 65, 116, 18, 224, 214, 2, 26, 213, 36, 82, 175, 176,
                  180, 191, 255, 46, 113, 134, 227, 253, 189, 81, 16, 97, 33, 114, 85>>,
              proof_of_integrity:
                <<0, 63, 70, 80, 109, 148, 124, 179, 105, 198, 92, 39, 212, 240, 48, 96, 69, 244,
                  213, 246, 75, 82, 83, 170, 121, 42, 105, 30, 23, 3, 231, 178, 153>>,
              ledger_operations: %LedgerOperations{
                fee: 0.01,
                transaction_movements: [],
                node_movements: [
                  %NodeMovement{
                    to:
                      <<0, 92, 208, 222, 119, 27, 128, 82, 69, 163, 128, 196, 105, 19, 18, 99,
                        217, 105, 80, 238, 155, 239, 91, 54, 82, 200, 16, 121, 32, 83, 63, 79,
                        88>>,
                    amount: 0.01
                  }
                ],
                unspent_outputs: []
              },
              signature:
                <<231, 4, 252, 234, 6, 126, 91, 87, 41, 70, 76, 220, 116, 238, 128, 189, 94, 124,
                  207, 90, 32, 143, 239, 153, 101, 148, 189, 125, 25, 235, 20, 207, 168, 10, 86,
                  59, 14, 249, 104, 144, 141, 151, 232, 149, 24, 189, 225, 56, 65, 208, 220, 202,
                  169, 166, 36, 248, 98, 108, 241, 114, 47, 102, 176, 212>>
            },
            cross_validation_stamps: [
              %CrossValidationStamp{
                node_public_key:
                  <<0, 161, 146, 84, 231, 250, 25, 216, 247, 158, 26, 32, 219, 6, 128, 253, 127,
                    119, 121, 206, 58, 142, 140, 194, 61, 235, 224, 193, 56, 82, 253, 19, 131>>,
                signature:
                  <<44, 66, 52, 214, 59, 145, 63, 7, 237, 115, 10, 255, 237, 85, 175, 115, 177,
                    85, 20, 76, 108, 118, 141, 190, 6, 84, 28, 134, 37, 235, 114, 30, 169, 151,
                    124, 242, 58, 26, 146, 125, 89, 64, 181, 253, 58, 199, 73, 12, 237, 134, 93,
                    73, 157, 123, 248, 199, 252, 138, 202, 227, 69, 83, 11, 29>>,
                inconsistencies: []
              }
            ]
          }
        ],
        unspent_outputs: [
          %UnspentOutput{
            from:
              <<0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
                159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
            amount: 10.5
          }
        ]
      }

      <<248::8, 0, 0, 0, 1, 0, 46, 140, 65, 49, 7, 111, 10, 130, 53, 72, 25, 43, 47, 81, 130, 161,
        225, 87, 144, 186, 117, 170, 105, 205, 173, 102, 49, 176, 8, 45, 49, 82, 2, 94, 245, 151,
        144, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 221, 122, 240, 119, 132, 26, 237,
        200, 88, 209, 23, 240, 176, 190, 89, 67, 120, 61, 106, 117, 10, 14, 12, 177, 171, 237, 66,
        113, 45, 18, 195, 249, 64, 206, 119, 19, 59, 13, 255, 98, 28, 80, 65, 115, 97, 216, 28,
        51, 237, 180, 94, 197, 228, 50, 240, 155, 61, 242, 17, 172, 225, 223, 8, 104, 220, 195,
        33, 46, 185, 88, 223, 224, 105, 41, 107, 67, 6, 92, 78, 15, 142, 47, 192, 214, 66, 124,
        30, 228, 167, 96, 61, 68, 188, 152, 246, 42, 246, 64, 238, 102, 94, 142, 31, 243, 44, 162,
        254, 161, 177, 121, 166, 204, 152, 126, 66, 207, 0, 75, 174, 126, 64, 226, 155, 92, 71,
        152, 119, 80, 150, 119, 88, 40, 110, 175, 135, 180, 179, 28, 57, 84, 35, 156, 173, 212,
        235, 155, 226, 41, 148, 171, 132, 196, 120, 51, 136, 4, 78, 123, 70, 44, 76, 162, 1, 0,
        206, 159, 122, 114, 106, 65, 116, 18, 224, 214, 2, 26, 213, 36, 82, 175, 176, 180, 191,
        255, 46, 113, 134, 227, 253, 189, 81, 16, 97, 33, 114, 85, 0, 63, 70, 80, 109, 148, 124,
        179, 105, 198, 92, 39, 212, 240, 48, 96, 69, 244, 213, 246, 75, 82, 83, 170, 121, 42, 105,
        30, 23, 3, 231, 178, 153, 63, 132, 122, 225, 71, 174, 20, 123, 0, 1, 0, 92, 208, 222, 119,
        27, 128, 82, 69, 163, 128, 196, 105, 19, 18, 99, 217, 105, 80, 238, 155, 239, 91, 54, 82,
        200, 16, 121, 32, 83, 63, 79, 88, 63, 132, 122, 225, 71, 174, 20, 123, 0, 64, 231, 4, 252,
        234, 6, 126, 91, 87, 41, 70, 76, 220, 116, 238, 128, 189, 94, 124, 207, 90, 32, 143, 239,
        153, 101, 148, 189, 125, 25, 235, 20, 207, 168, 10, 86, 59, 14, 249, 104, 144, 141, 151,
        232, 149, 24, 189, 225, 56, 65, 208, 220, 202, 169, 166, 36, 248, 98, 108, 241, 114, 47,
        102, 176, 212, 1, 0, 161, 146, 84, 231, 250, 25, 216, 247, 158, 26, 32, 219, 6, 128, 253,
        127, 119, 121, 206, 58, 142, 140, 194, 61, 235, 224, 193, 56, 82, 253, 19, 131, 64, 44,
        66, 52, 214, 59, 145, 63, 7, 237, 115, 10, 255, 237, 85, 175, 115, 177, 85, 20, 76, 108,
        118, 141, 190, 6, 84, 28, 134, 37, 235, 114, 30, 169, 151, 124, 242, 58, 26, 146, 125, 89,
        64, 181, 253, 58, 199, 73, 12, 237, 134, 93, 73, 157, 123, 248, 199, 252, 138, 202, 227,
        69, 83, 11, 29, 0, 0, 0, 0, 1, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129,
        145, 126, 45, 68, 194, 159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251,
        186, 64, 37, 0, 0, 0, 0, 0, 0>> = Message.encode(msg)
    end

    test "should serialize a Balance message" do
      msg = %Balance{
        uco: 10.5
      }

      assert <<247::8, 64, 37, 0, 0, 0, 0, 0, 0>> = Message.encode(msg)
    end

    test "should serialize a EncryptedStorageNonce message" do
      msg = %EncryptedStorageNonce{
        digest:
          <<113, 15, 188, 151, 173, 16, 195, 140, 160, 244, 75, 59, 47, 220, 113, 96, 241, 34, 99,
            157, 115, 207, 195, 78, 32, 175, 171, 213, 154, 54, 113, 236>>
      }

      assert <<246::8, 113, 15, 188, 151, 173, 16, 195, 140, 160, 244, 75, 59, 47, 220, 113, 96,
               241, 34, 99, 157, 115, 207, 195, 78, 32, 175, 171, 213, 154, 54, 113,
               236>> = Message.encode(msg)
    end

    test "should serialize a ProofOfIntegrity message" do
      address = :crypto.strong_rand_bytes(32)

      msg = %ProofOfIntegrity{
        digest: address
      }

      assert <<245::8, address::binary>> == Message.encode(msg)
    end

    test "should serialize a BootstrappingNodes message" do
      msg = %BootstrappingNodes{
        new_seeds: [
          %Node{
            ip: {127, 0, 0, 1},
            port: 3000,
            first_public_key:
              <<0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64,
                92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226>>,
            last_public_key:
              <<0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64,
                92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226>>,
            geo_patch: "FA9",
            network_patch: "AVC",
            available?: true,
            average_availability: 0.8,
            enrollment_date: ~U[2020-06-26 08:36:11Z],
            ready_date: ~U[2020-06-26 08:36:11Z],
            ready?: true,
            authorization_date: ~U[2020-06-26 08:36:11Z],
            authorized?: true
          }
        ],
        closest_nodes: [
          %Node{
            ip: {127, 0, 0, 1},
            port: 3000,
            first_public_key:
              <<0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64,
                92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226>>,
            last_public_key:
              <<0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64,
                92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226>>,
            geo_patch: "FA9",
            network_patch: "AVC",
            available?: true,
            average_availability: 0.8,
            enrollment_date: ~U[2020-06-26 08:36:11Z],
            ready_date: ~U[2020-06-26 08:36:11Z],
            ready?: true,
            authorization_date: ~U[2020-06-26 08:36:11Z],
            authorized?: true
          }
        ]
      }

      assert <<244::8, 1::8, 127, 0, 0, 1, 11, 184, "FA9", "AVC", 80, 94, 245, 179, 123, 1::1,
               1::1, 94, 245, 179, 123, 1::1, 94, 245, 179, 123, 0, 182, 67, 168, 252, 227, 203,
               142, 164, 142, 248, 159, 209, 249, 247, 86, 64, 92, 224, 91, 182, 122, 49, 209,
               169, 96, 111, 219, 204, 57, 250, 59, 226, 0, 182, 67, 168, 252, 227, 203, 142, 164,
               142, 248, 159, 209, 249, 247, 86, 64, 92, 224, 91, 182, 122, 49, 209, 169, 96, 111,
               219, 204, 57, 250, 59, 226, 1::8, 127, 0, 0, 1, 11, 184, "FA9", "AVC", 80, 94, 245,
               179, 123, 1::1, 1::1, 94, 245, 179, 123, 1::1, 94, 245, 179, 123, 0, 182, 67, 168,
               252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64, 92, 224, 91, 182,
               122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226, 0, 182, 67, 168, 252, 227,
               203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64, 92, 224, 91, 182, 122, 49,
               209, 169, 96, 111, 219, 204, 57, 250, 59, 226>> = Message.encode(msg)
    end
  end

  describe "wrap_binary/1" do
    test "should return entire bytes if the bitstring is a binary" do
      assert <<_::binary-size(33)>> = Message.wrap_binary(:crypto.strong_rand_bytes(33))
    end

    test "should wraps bitstring into a full binary" do
      assert <<_::8>> = Message.wrap_binary(<<1::1, 1::1, 1::1>>)

      bitstring = Enum.map(1..60, fn _ -> <<1::1>> end) |> :erlang.list_to_bitstring()
      assert <<_::64>> = Message.wrap_binary(bitstring)
    end
  end
end
