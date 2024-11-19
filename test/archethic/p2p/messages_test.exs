defmodule Archethic.P2P.MessageTest do
  use ArchethicCase

  import ArchethicCase

  alias Archethic.Contracts.Contract
  alias Archethic.Crypto
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message

  alias Archethic.P2P.Message.{
    AcknowledgeStorage,
    BootstrappingNodes,
    CrossValidate,
    CrossValidationDone,
    EncryptedStorageNonce,
    Error,
    FirstPublicKey,
    GetBootstrappingNodes,
    GetFirstPublicKey,
    GetLastTransaction,
    GetLastTransactionAddress,
    GetStorageNonce,
    GetTransaction,
    GetTransactionChain,
    GetTransactionChainLength,
    GetTransactionInputs,
    GetTransactionSummary,
    LastTransactionAddress,
    ListNodes,
    NewTransaction,
    NodeList,
    NotFound,
    NotifyEndOfNodeSync,
    NotifyLastTransactionAddress,
    NotifyPreviousChain,
    Ok,
    Ping,
    RegisterBeaconUpdates,
    ReplicateTransaction,
    StartMining,
    ShardRepair,
    TransactionChainLength,
    TransactionInputList,
    TransactionList
  }

  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
  alias Archethic.TransactionChain.Transaction.ProofOfValidation
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionFactory

  doctest Message

  describe "symmetric encoding/decoding of" do
    test "GetBootstrappingNodes message" do
      assert %GetBootstrappingNodes{patch: "AAA"} ==
               %GetBootstrappingNodes{patch: "AAA"}
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "GetStorageNonce message" do
      {public_key, _} = Crypto.generate_deterministic_keypair("seed", :secp256r1)

      assert %GetStorageNonce{public_key: public_key} ==
               %GetStorageNonce{public_key: public_key}
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "ListNodes message" do
      assert %ListNodes{authorized_and_available?: true} =
               %ListNodes{authorized_and_available?: true}
               |> Message.encode()
               |> Message.decode()
               |> elem(0)

      assert %ListNodes{authorized_and_available?: false} =
               %ListNodes{authorized_and_available?: false}
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "GetTransaction message" do
      address = <<0::8>> <> <<0::8>> <> :crypto.strong_rand_bytes(32)

      assert %GetTransaction{address: address} ==
               %GetTransaction{address: address}
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "GetTransactionChain message" do
      address = random_address()
      paging_address = random_address()
      from = DateTime.utc_now() |> DateTime.truncate(:second)

      assert %GetTransactionChain{address: address} ==
               %GetTransactionChain{address: address}
               |> Message.encode()
               |> Message.decode()
               |> elem(0)

      assert %GetTransactionChain{address: address, paging_state: paging_address} ==
               %GetTransactionChain{address: address, paging_state: paging_address}
               |> Message.encode()
               |> Message.decode()
               |> elem(0)

      assert %GetTransactionChain{address: address, order: :desc} ==
               %GetTransactionChain{address: address, order: :desc}
               |> Message.encode()
               |> Message.decode()
               |> elem(0)

      assert %GetTransactionChain{address: address, order: :asc, paging_state: from} ==
               %GetTransactionChain{address: address, order: :asc, paging_state: from}
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "NewTransaction message" do
      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      # no context
      assert %NewTransaction{transaction: tx, welcome_node: Crypto.first_node_public_key()} ==
               %NewTransaction{transaction: tx, welcome_node: Crypto.first_node_public_key()}
               |> Message.encode()
               |> Message.decode()
               |> elem(0)

      # with contract context
      ctx = %Contract.Context{
        trigger: {:oracle, random_address()},
        status: :tx_output,
        timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
      }

      assert %NewTransaction{
               transaction: tx,
               welcome_node: Crypto.first_node_public_key(),
               contract_context: ctx
             } ==
               %NewTransaction{
                 transaction: tx,
                 welcome_node: Crypto.first_node_public_key(),
                 contract_context: ctx
               }
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "StartMining message" do
      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)
      {welcome_node_public_key, _} = Crypto.generate_deterministic_keypair("wkey")

      validation_node_public_keys =
        Enum.map(1..10, fn i ->
          {pub, _} = Crypto.generate_deterministic_keypair("vkey" <> Integer.to_string(i))
          pub
        end)

      network_hash = :crypto.hash(:sha256, "networkview")
      p2p_hash = :crypto.hash(:sha256, "p2pview")
      ref_timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)

      # no context
      assert %StartMining{
               transaction: tx,
               welcome_node_public_key: welcome_node_public_key,
               validation_node_public_keys: validation_node_public_keys,
               network_chains_view_hash: network_hash,
               p2p_view_hash: p2p_hash,
               ref_timestamp: ref_timestamp
             } ==
               %StartMining{
                 transaction: tx,
                 welcome_node_public_key: welcome_node_public_key,
                 validation_node_public_keys: validation_node_public_keys,
                 network_chains_view_hash: network_hash,
                 p2p_view_hash: p2p_hash,
                 ref_timestamp: ref_timestamp
               }
               |> Message.encode()
               |> Message.decode()
               |> elem(0)

      # with contract context
      ctx = %Contract.Context{
        trigger: {:datetime, DateTime.utc_now() |> DateTime.truncate(:second)},
        status: :tx_output,
        timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
      }

      assert %StartMining{
               transaction: tx,
               welcome_node_public_key: welcome_node_public_key,
               validation_node_public_keys: validation_node_public_keys,
               network_chains_view_hash: network_hash,
               p2p_view_hash: p2p_hash,
               contract_context: ctx,
               ref_timestamp: ref_timestamp
             } ==
               %StartMining{
                 transaction: tx,
                 welcome_node_public_key: welcome_node_public_key,
                 validation_node_public_keys: validation_node_public_keys,
                 network_chains_view_hash: network_hash,
                 p2p_view_hash: p2p_hash,
                 contract_context: ctx,
                 ref_timestamp: ref_timestamp
               }
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "CrossValidate message" do
      msg = %CrossValidate{
        address:
          <<0, 0, 227, 129, 244, 35, 48, 113, 14, 75, 1, 127, 107, 32, 29, 93, 232, 119, 254, 1,
            65, 32, 47, 129, 164, 142, 240, 43, 22, 81, 188, 212, 56, 238>>,
        validation_stamp: %ValidationStamp{
          timestamp: ~U[2020-06-26 06:37:04.000Z],
          proof_of_work:
            <<0, 0, 206, 159, 122, 114, 106, 65, 116, 18, 224, 214, 2, 26, 213, 36, 82, 175, 176,
              180, 191, 255, 46, 113, 134, 227, 253, 189, 81, 16, 97, 33, 114, 85>>,
          proof_of_integrity:
            <<0, 63, 70, 80, 109, 148, 124, 179, 105, 198, 92, 39, 212, 240, 48, 96, 69, 244, 213,
              246, 75, 82, 83, 170, 121, 42, 105, 30, 23, 3, 231, 178, 153>>,
          proof_of_election:
            <<74, 224, 26, 42, 253, 85, 104, 246, 72, 244, 189, 182, 165, 94, 92, 20, 166, 149,
              124, 246, 219, 170, 160, 168, 206, 214, 236, 215, 211, 121, 95, 149, 132, 136, 114,
              244, 132, 44, 255, 222, 98, 76, 247, 125, 45, 170, 95, 51, 46, 229, 21, 32, 226, 99,
              16, 5, 107, 207, 32, 240, 23, 85, 219, 247>>,
          ledger_operations: %LedgerOperations{
            fee: 1_000_000,
            transaction_movements: [],
            unspent_outputs: []
          },
          signature:
            <<231, 4, 252, 234, 6, 126, 91, 87, 41, 70, 76, 220, 116, 238, 128, 189, 94, 124, 207,
              90, 32, 143, 239, 153, 101, 148, 189, 125, 25, 235, 20, 207, 168, 10, 86, 59, 14,
              249, 104, 144, 141, 151, 232, 149, 24, 189, 225, 56, 65, 208, 220, 202, 169, 166,
              36, 248, 98, 108, 241, 114, 47, 102, 176, 212>>,
          protocol_version: ArchethicCase.current_protocol_version()
        },
        replication_tree: %{
          chain: [<<1::1, 0::1, 1::1>>, <<0::1, 1::1, 0::1>>, <<1::1, 0::1, 0::1>>],
          beacon: [<<1::1, 0::1, 1::1>>, <<0::1, 1::1, 0::1>>, <<1::1, 0::1, 0::1>>],
          IO: [<<1::1, 0::1, 1::1>>, <<0::1, 1::1, 0::1>>, <<1::1, 0::1, 0::1>>]
        },
        confirmed_validation_nodes: <<1::1, 1::1>>,
        aggregated_utxos: [
          %VersionedUnspentOutput{
            protocol_version: ArchethicCase.current_protocol_version(),
            unspent_output: %UnspentOutput{
              from: ArchethicCase.random_address(),
              type: :UCO,
              amount: 100_000_000,
              timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
            }
          }
        ]
      }

      assert msg ==
               msg
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "CrossValidate message with different replication trees" do
      msg = %CrossValidate{
        address:
          <<0, 0, 227, 129, 244, 35, 48, 113, 14, 75, 1, 127, 107, 32, 29, 93, 232, 119, 254, 1,
            65, 32, 47, 129, 164, 142, 240, 43, 22, 81, 188, 212, 56, 238>>,
        validation_stamp: %ValidationStamp{
          timestamp: ~U[2020-06-26 06:37:04.000Z],
          proof_of_work:
            <<0, 0, 206, 159, 122, 114, 106, 65, 116, 18, 224, 214, 2, 26, 213, 36, 82, 175, 176,
              180, 191, 255, 46, 113, 134, 227, 253, 189, 81, 16, 97, 33, 114, 85>>,
          proof_of_integrity:
            <<0, 63, 70, 80, 109, 148, 124, 179, 105, 198, 92, 39, 212, 240, 48, 96, 69, 244, 213,
              246, 75, 82, 83, 170, 121, 42, 105, 30, 23, 3, 231, 178, 153>>,
          proof_of_election:
            <<74, 224, 26, 42, 253, 85, 104, 246, 72, 244, 189, 182, 165, 94, 92, 20, 166, 149,
              124, 246, 219, 170, 160, 168, 206, 214, 236, 215, 211, 121, 95, 149, 132, 136, 114,
              244, 132, 44, 255, 222, 98, 76, 247, 125, 45, 170, 95, 51, 46, 229, 21, 32, 226, 99,
              16, 5, 107, 207, 32, 240, 23, 85, 219, 247>>,
          ledger_operations: %LedgerOperations{
            fee: 1_000_000,
            transaction_movements: [],
            unspent_outputs: []
          },
          signature:
            <<231, 4, 252, 234, 6, 126, 91, 87, 41, 70, 76, 220, 116, 238, 128, 189, 94, 124, 207,
              90, 32, 143, 239, 153, 101, 148, 189, 125, 25, 235, 20, 207, 168, 10, 86, 59, 14,
              249, 104, 144, 141, 151, 232, 149, 24, 189, 225, 56, 65, 208, 220, 202, 169, 166,
              36, 248, 98, 108, 241, 114, 47, 102, 176, 212>>,
          protocol_version: ArchethicCase.current_protocol_version()
        },
        replication_tree: %{
          chain: [
            <<1::1, 0::1, 1::1, 0::1>>,
            <<0::1, 1::1, 0::1, 1::1>>,
            <<1::1, 0::1, 0::1, 0::1>>
          ],
          beacon: [<<1::1, 0::1>>, <<0::1, 1::1>>, <<0::1, 0::1>>],
          IO: [<<1::1, 0::1>>, <<0::1, 1::1>>, <<0::1, 0::1>>]
        },
        confirmed_validation_nodes: <<1::1, 1::1>>,
        aggregated_utxos: [
          %VersionedUnspentOutput{
            protocol_version: ArchethicCase.current_protocol_version(),
            unspent_output: %UnspentOutput{
              from: ArchethicCase.random_address(),
              type: :UCO,
              amount: 100_000_000,
              timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
            }
          }
        ]
      }

      assert msg ==
               msg
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "CrossValidationDone message" do
      msg = %CrossValidationDone{
        address:
          <<0, 0, 227, 129, 244, 35, 48, 113, 14, 75, 1, 127, 107, 32, 29, 93, 232, 119, 254, 1,
            65, 32, 47, 129, 164, 142, 240, 43, 22, 81, 188, 212, 56, 238>>,
        cross_validation_stamp: %CrossValidationStamp{
          node_public_key:
            <<0, 0, 92, 208, 222, 119, 27, 128, 82, 69, 163, 128, 196, 105, 19, 18, 99, 217, 105,
              80, 238, 155, 239, 91, 54, 82, 200, 16, 121, 32, 83, 63, 79, 88>>,
          signature:
            <<231, 4, 252, 234, 6, 126, 91, 87, 41, 70, 76, 220, 116, 238, 128, 189, 94, 124, 207,
              90, 32, 143, 239, 153, 101, 148, 189, 125, 25, 235, 20, 207, 168, 10, 86, 59, 14,
              249, 104, 144, 141, 151, 232, 149, 24, 189, 225, 56, 65, 208, 220, 202, 169, 166,
              36, 248, 98, 108, 241, 114, 47, 102, 176, 212>>,
          inconsistencies: []
        }
      }

      assert msg ==
               msg
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "ReplicateTransaction message" do
      tx = TransactionFactory.create_valid_transaction()

      msg = %ReplicateTransaction{
        transaction: tx,
        genesis_address: random_address(),
        proof_of_validation: %ProofOfValidation{
          signature: :crypto.strong_rand_bytes(96),
          nodes_bitmask: <<1::1>>
        }
      }

      assert msg == msg |> Message.encode() |> Message.decode() |> elem(0)
    end

    test "AcknowledgeStorage message" do
      signature = :crypto.strong_rand_bytes(32)
      tx_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      assert %AcknowledgeStorage{
               signature: signature,
               address: tx_address
             } ==
               %AcknowledgeStorage{
                 signature: signature,
                 address: tx_address
               }
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "NotifyEndOfNodeSync message" do
      msg = %NotifyEndOfNodeSync{
        node_public_key:
          <<0, 0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
            100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241>>,
        timestamp: ~U[2020-06-25 15:11:53Z] |> DateTime.truncate(:second)
      }

      assert msg ==
               msg
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "GetLastTransaction message" do
      address = <<0::8>> <> <<0::8>> <> :crypto.strong_rand_bytes(32)

      assert %GetLastTransaction{
               address: address
             } ==
               %GetLastTransaction{
                 address: address
               }
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "GetTransactionInputs message" do
      address = <<0::8>> <> <<0::8>> <> :crypto.strong_rand_bytes(32)

      assert %GetTransactionInputs{
               address: address
             } ==
               %GetTransactionInputs{
                 address: address
               }
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "Ok message" do
      assert %Ok{} == %Ok{} |> Message.encode() |> Message.decode() |> elem(0)
    end

    test "NotFound message" do
      assert %NotFound{} == %NotFound{} |> Message.encode() |> Message.decode() |> elem(0)
    end

    test "Transaction message" do
      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      assert tx ==
               tx
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "TransactionList message" do
      msg = %TransactionList{
        transactions: [
          TransactionFactory.create_valid_transaction(),
          TransactionFactory.create_valid_transaction()
        ]
      }

      assert {msg, <<>>} == msg |> Message.encode() |> Message.decode()
    end

    test "NodeList message" do
      msg = %NodeList{
        nodes: [
          %Node{
            ip: {127, 0, 0, 1},
            port: 3000,
            http_port: 4000,
            first_public_key: ArchethicCase.random_public_key(),
            last_public_key: ArchethicCase.random_public_key(),
            geo_patch: "FA9",
            network_patch: "AVC",
            available?: true,
            average_availability: 0.8,
            enrollment_date: ~U[2020-06-26 08:36:11Z],
            authorization_date: ~U[2020-06-26 08:36:11Z],
            authorized?: true,
            last_address: ArchethicCase.random_address(),
            reward_address: ArchethicCase.random_address(),
            origin_public_key: ArchethicCase.random_public_key(),
            mining_public_key: ArchethicCase.random_public_key()
          }
        ]
      }

      assert msg ==
               msg
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "EncryptedStorageNonce message" do
      msg = %EncryptedStorageNonce{
        digest:
          <<113, 15, 188, 151, 173, 16, 195, 140, 160, 244, 75, 59, 47, 220, 113, 96, 241, 34, 99,
            157, 115, 207, 195, 78, 32, 175, 171, 213, 154, 54, 113, 236>>
      }

      assert msg ==
               msg
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "BootstrappingNodes message" do
      msg = %BootstrappingNodes{
        new_seeds: [
          %Node{
            ip: {127, 0, 0, 1},
            port: 3000,
            http_port: 4000,
            first_public_key: ArchethicCase.random_public_key(),
            last_public_key: ArchethicCase.random_public_key(),
            geo_patch: "FA9",
            network_patch: "AVC",
            available?: true,
            average_availability: 0.8,
            enrollment_date: ~U[2020-06-26 08:36:11Z],
            authorization_date: ~U[2020-06-26 08:36:11Z],
            authorized?: true,
            reward_address: ArchethicCase.random_address(),
            last_address: ArchethicCase.random_address(),
            origin_public_key: ArchethicCase.random_public_key(),
            mining_public_key: ArchethicCase.random_public_key()
          }
        ],
        closest_nodes: [
          %Node{
            ip: {127, 0, 0, 1},
            port: 3000,
            http_port: 4000,
            first_public_key: ArchethicCase.random_public_key(),
            last_public_key: ArchethicCase.random_public_key(),
            geo_patch: "FA9",
            network_patch: "AVC",
            available?: true,
            average_availability: 0.8,
            enrollment_date: ~U[2020-06-26 08:36:11Z],
            authorization_date: ~U[2020-06-26 08:36:11Z],
            authorized?: true,
            reward_address: ArchethicCase.random_address(),
            last_address: ArchethicCase.random_address(),
            origin_public_key: ArchethicCase.random_public_key(),
            mining_public_key: ArchethicCase.random_public_key()
          }
        ],
        first_enrolled_node: %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          http_port: 4000,
          first_public_key: ArchethicCase.random_public_key(),
          last_public_key: ArchethicCase.random_public_key(),
          geo_patch: "FA9",
          network_patch: "AVC",
          available?: true,
          average_availability: 0.8,
          enrollment_date: ~U[2020-06-26 08:36:11Z],
          authorization_date: ~U[2020-06-26 08:36:11Z],
          authorized?: true,
          reward_address: ArchethicCase.random_address(),
          last_address: ArchethicCase.random_address(),
          origin_public_key: ArchethicCase.random_public_key(),
          mining_public_key: ArchethicCase.random_public_key()
        }
      }

      assert msg ==
               msg
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "GetTransactionChainLength message" do
      address = <<0::8>> <> <<0::8>> <> :crypto.strong_rand_bytes(32)

      msg = %GetTransactionChainLength{
        address: address
      }

      assert msg ==
               msg
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "TransactionChainLength message" do
      msg = %TransactionChainLength{
        length: 1000
      }

      assert msg ==
               msg
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "TransactionInputList message" do
      msg = %TransactionInputList{
        inputs: [
          %VersionedTransactionInput{
            input: %TransactionInput{
              from:
                <<0, 0, 147, 31, 74, 190, 86, 56, 43, 83, 35, 166, 128, 254, 235, 43, 129, 108,
                  57, 44, 182, 107, 61, 17, 190, 54, 143, 148, 85, 204, 22, 168, 139, 206>>,
              amount: 1_050_000_000,
              spent?: true,
              type: :UCO,
              timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
            },
            protocol_version: 1
          },
          %VersionedTransactionInput{
            input: %TransactionInput{
              from:
                <<0, 0, 147, 31, 74, 190, 86, 56, 43, 83, 35, 166, 128, 254, 235, 43, 129, 108,
                  57, 44, 182, 107, 61, 17, 190, 54, 143, 148, 85, 204, 22, 168, 139, 206>>,
              type: :call,
              timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
            },
            protocol_version: 1
          }
        ]
      }

      assert msg ==
               msg
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "GetFirstPublicKey message" do
      msg = %GetFirstPublicKey{
        public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      }

      assert msg ==
               msg
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "FirstPublicKey message" do
      msg = %FirstPublicKey{
        public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      }

      assert msg ==
               msg
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "GetLastTransactionAddress message" do
      msg = %GetLastTransactionAddress{
        address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        timestamp: DateTime.truncate(DateTime.utc_now(), :millisecond)
      }

      assert msg ==
               msg
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "LastTransactionAddress message" do
      msg = %LastTransactionAddress{
        address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
      }

      assert msg ==
               msg
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "NotifyLastTransactionAddress message" do
      msg = %NotifyLastTransactionAddress{
        last_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        genesis_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        previous_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
      }

      assert msg ==
               msg
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "NotifyPreviousChain message" do
      msg = %NotifyPreviousChain{
        address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      }

      assert msg ==
               msg
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "GetTransactionSummary message" do
      msg = %GetTransactionSummary{
        address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      }

      assert msg ==
               msg
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "Ping message" do
      msg = %Ping{}

      assert msg ==
               msg
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "Error message" do
      msg = %Error{reason: :invalid_transaction}

      assert msg ==
               msg
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "Register beacon updates" do
      subset = <<0>>
      node_public_key = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      msg = %RegisterBeaconUpdates{
        subset: subset,
        node_public_key: node_public_key
      }

      assert msg ==
               msg
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end

    test "%ShardRepair" do
      msg = %ShardRepair{
        genesis_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        storage_address: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        io_addresses: [
          <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
        ]
      }

      assert msg ==
               msg
               |> Message.encode()
               |> Message.decode()
               |> elem(0)
    end
  end

  test "get_timeout should return timeout according to message type" do
    assert 3_000 ==
             Message.get_timeout(%GetStorageNonce{public_key: ArchethicCase.random_public_key()})

    assert 25_165 == Message.get_timeout(%GetTransaction{address: "123"})
  end
end
