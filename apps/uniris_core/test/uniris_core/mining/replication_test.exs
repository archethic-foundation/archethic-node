defmodule UnirisCore.Mining.ReplicationTest do
  use UnirisCoreCase, async: false

  @moduletag capture_log: true

  alias UnirisCore.Mining.Replication
  alias UnirisCore.Mining.Context
  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations.Movement
  alias UnirisCore.Transaction.CrossValidationStamp
  alias UnirisCore.Crypto
  alias UnirisCore.Beacon
  alias UnirisCore.BeaconSlot.TransactionInfo
  alias UnirisCore.BeaconSlotTimer
  alias UnirisCore.BeaconSubsets
  alias UnirisCore.BeaconSubset
  alias UnirisCore.BeaconSubsetRegistry
  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node

  import Mox

  test "tree/2 create tree of storage nodes grouped by the closest validation nodes" do
    validation_nodes = [
      %{network_patch: "AC2", last_public_key: "key_v1"},
      %{network_patch: "DF3", last_public_key: "key_v2"},
      %{network_patch: "C22", last_public_key: "key_v3"},
      %{network_patch: "E19", last_public_key: "key_v4"},
      %{network_patch: "22A", last_public_key: "key_v5"}
    ]

    storage_nodes = [
      %{network_patch: "F36", first_public_key: "key_S1", last_public_key: "key_S1"},
      %{network_patch: "A23", first_public_key: "key_S2", last_public_key: "key_S2"},
      %{network_patch: "B43", first_public_key: "key_S3", last_public_key: "key_S3"},
      %{network_patch: "2A9", first_public_key: "key_S4", last_public_key: "key_S4"},
      %{network_patch: "143", first_public_key: "key_S5", last_public_key: "key_S5"},
      %{network_patch: "BB2", first_public_key: "key_S6", last_public_key: "key_S6"},
      %{network_patch: "A63", first_public_key: "key_S7", last_public_key: "key_S7"},
      %{network_patch: "D32", first_public_key: "key_S8", last_public_key: "key_S8"},
      %{network_patch: "19A", first_public_key: "key_S9", last_public_key: "key_S9"},
      %{network_patch: "C2A", first_public_key: "key_S10", last_public_key: "key_S10"},
      %{network_patch: "C23", first_public_key: "key_S11", last_public_key: "key_S11"},
      %{network_patch: "F22", first_public_key: "key_S12", last_public_key: "key_S12"},
      %{network_patch: "E2B", first_public_key: "key_S13", last_public_key: "key_S13"},
      %{network_patch: "AA0", first_public_key: "key_S14", last_public_key: "key_S14"},
      %{network_patch: "042", first_public_key: "key_S15", last_public_key: "key_S15"},
      %{network_patch: "3BC", first_public_key: "key_S16", last_public_key: "key_S16"}
    ]

    tree = Replication.tree(validation_nodes, storage_nodes)

    assert tree ==
             %{
               "key_v1" => [
                 %{network_patch: "A23", first_public_key: "key_S2", last_public_key: "key_S2"},
                 %{network_patch: "B43", first_public_key: "key_S3", last_public_key: "key_S3"},
                 %{network_patch: "A63", first_public_key: "key_S7", last_public_key: "key_S7"},
                 %{network_patch: "AA0", first_public_key: "key_S14", last_public_key: "key_S14"}
               ],
               "key_v2" => [
                 %{network_patch: "D32", first_public_key: "key_S8", last_public_key: "key_S8"}
               ],
               "key_v3" => [
                 %{network_patch: "BB2", first_public_key: "key_S6", last_public_key: "key_S6"},
                 %{network_patch: "C2A", first_public_key: "key_S10", last_public_key: "key_S10"},
                 %{network_patch: "C23", first_public_key: "key_S11", last_public_key: "key_S11"}
               ],
               "key_v4" => [
                 %{network_patch: "F36", first_public_key: "key_S1", last_public_key: "key_S1"},
                 %{network_patch: "F22", first_public_key: "key_S12", last_public_key: "key_S12"},
                 %{network_patch: "E2B", first_public_key: "key_S13", last_public_key: "key_S13"}
               ],
               "key_v5" => [
                 %{network_patch: "2A9", first_public_key: "key_S4", last_public_key: "key_S4"},
                 %{network_patch: "143", first_public_key: "key_S5", last_public_key: "key_S5"},
                 %{network_patch: "19A", first_public_key: "key_S9", last_public_key: "key_S9"},
                 %{network_patch: "042", first_public_key: "key_S15", last_public_key: "key_S15"},
                 %{network_patch: "3BC", first_public_key: "key_S16", last_public_key: "key_S16"}
               ]
             }
  end

  describe "valid_transaction?/2" do
    test "should return false when the proof of work is not found" do
      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      tx = %{
        tx
        | validation_stamp: %ValidationStamp{
            proof_of_work: "",
            proof_of_integrity: "",
            ledger_operations: %LedgerOperations{},
            signature: ""
          }
      }

      assert false == Replication.valid_transaction?(tx)
    end

    test "should return false when the proof of integrity is empty" do
      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      tx = %{
        tx
        | validation_stamp: %ValidationStamp{
            proof_of_work: :crypto.strong_rand_bytes(32),
            proof_of_integrity: "",
            ledger_operations: %LedgerOperations{},
            signature: ""
          }
      }

      assert false == Replication.valid_transaction?(tx)
    end

    test "should return false when there less than 2 node movements" do
      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      tx = %{
        tx
        | validation_stamp: %ValidationStamp{
            proof_of_work: :crypto.strong_rand_bytes(32),
            proof_of_integrity: :crypto.strong_rand_bytes(32),
            ledger_operations: %LedgerOperations{
              fee: 1.0,
              node_movements: []
            },
            signature: ""
          }
      }

      assert false == Replication.valid_transaction?(tx)
    end

    test "should return false when the validation stamp signature is invalid" do
      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      stamp = %ValidationStamp{
        proof_of_work: :crypto.strong_rand_bytes(32),
        proof_of_integrity: :crypto.strong_rand_bytes(32),
        ledger_operations: %LedgerOperations{
          node_movements: [
            %Movement{to: :crypto.strong_rand_bytes(32), amount: 0.0},
            %Movement{to: Crypto.node_public_key(), amount: 0.0}
          ]
        },
        signature: ""
      }

      cross_validation_stamps = [CrossValidationStamp.new(stamp, [])]

      tx = %{
        tx
        | validation_stamp: stamp,
          cross_validation_stamps: cross_validation_stamps
      }

      assert false == Replication.valid_transaction?(tx)
    end

    test "should return false when the the proof of work is invalid" do
      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      stamp = %{
        proof_of_work: <<0>> <> :crypto.strong_rand_bytes(32),
        proof_of_integrity: :crypto.strong_rand_bytes(32),
        ledger_operations: %LedgerOperations{
          node_movements: [
            %Movement{to: :crypto.strong_rand_bytes(32), amount: 0.0},
            %Movement{to: Crypto.node_public_key(), amount: 0.0}
          ]
        }
      }

      sig = Crypto.sign_with_node_key(stamp)
      stamp = struct!(ValidationStamp, Map.put(stamp, :signature, sig))
      cross_validation_stamps = [CrossValidationStamp.new(stamp, [])]

      tx = %{
        tx
        | validation_stamp: stamp,
          cross_validation_stamps: cross_validation_stamps
      }

      assert false == Replication.valid_transaction?(tx)
    end

    test "should return false when the fee is invalid" do
      tx = Transaction.new(:node, %TransactionData{})

      stamp = %{
        proof_of_work: Crypto.node_public_key(0),
        proof_of_integrity: :crypto.strong_rand_bytes(32),
        ledger_operations: %LedgerOperations{
          fee: 5.5,
          node_movements: [
            %Movement{to: :crypto.strong_rand_bytes(32), amount: 0.0},
            %Movement{to: Crypto.node_public_key(), amount: 0.0}
          ]
        }
      }

      sig = Crypto.sign_with_node_key(stamp)
      stamp = struct!(ValidationStamp, Map.put(stamp, :signature, sig))
      cross_validation_stamps = [CrossValidationStamp.new(stamp, [])]

      tx = %{tx | validation_stamp: stamp, cross_validation_stamps: cross_validation_stamps}

      assert false == Replication.valid_transaction?(tx)
    end

    test "should return false when the total rewards is invalid" do
      tx = Transaction.new(:node, %TransactionData{})

      stamp = %{
        proof_of_work: Crypto.node_public_key(0),
        proof_of_integrity: :crypto.strong_rand_bytes(32),
        ledger_operations: %LedgerOperations{
          fee: 0.0,
          node_movements: [
            %Movement{to: :crypto.strong_rand_bytes(32), amount: 1},
            %Movement{to: Crypto.node_public_key(), amount: 3}
          ]
        }
      }

      sig = Crypto.sign_with_node_key(stamp)
      stamp = struct!(ValidationStamp, Map.put(stamp, :signature, sig))
      cross_validation_stamps = [CrossValidationStamp.new(stamp, [])]

      tx = %{tx | validation_stamp: stamp, cross_validation_stamps: cross_validation_stamps}

      assert false == Replication.valid_transaction?(tx)
    end

    test "should return false when cross validation stamp are invalid" do
      tx = Transaction.new(:node, %TransactionData{})

      stamp =
        ValidationStamp.new(tx, %Context{}, "welcome_node_public_key", Crypto.node_public_key(), [
          "cross_validation_node"
        ])

      cross_validation_stamps = [
        %CrossValidationStamp{
          signature: "",
          inconsistencies: [],
          node_public_key: Crypto.node_public_key()
        }
      ]

      tx = %{tx | validation_stamp: stamp, cross_validation_stamps: cross_validation_stamps}

      assert false == Replication.valid_transaction?(tx)
    end

    test "should return false when atomic commitment is not reached" do
      tx = Transaction.new(:node, %TransactionData{})

      stamp =
        ValidationStamp.new(tx, %Context{}, "welcome_node_public_key", Crypto.node_public_key(), [
          "cross_validation_node"
        ])

      cross_validation_stamps = [
        CrossValidationStamp.new(stamp, []),
        CrossValidationStamp.new(stamp, [:proof_of_work])
      ]

      tx = %{tx | validation_stamp: stamp, cross_validation_stamps: cross_validation_stamps}

      assert false == Replication.valid_transaction?(tx)
    end

    test "should return false when cross validation nodes are not rewarded" do
      tx = Transaction.new(:node, %TransactionData{})

      stamp =
        ValidationStamp.new(tx, %Context{}, "welcome_node_public_key", Crypto.node_public_key(), [
          "cross_validation_node"
        ])

      {pub, pv} = Crypto.generate_deterministic_keypair("other_seed", :secp256r1)

      cross_validation_stamps = [
        %CrossValidationStamp{
          signature: Crypto.sign(stamp, pv),
          inconsistencies: [],
          node_public_key: pub
        }
      ]

      tx = %{tx | validation_stamp: stamp, cross_validation_stamps: cross_validation_stamps}

      assert false == Replication.valid_transaction?(tx)
    end

    test "should return false when the proof of integrity is invalid" do
      tx = Transaction.new(:node, %TransactionData{})

      stamp =
        ValidationStamp.new(tx, %Context{}, "welcome_node_public_key", Crypto.node_public_key(), [
          "cross_validation_node"
        ])

      cross_validation_stamps = [
        CrossValidationStamp.new(stamp, [])
      ]

      tx = %{tx | validation_stamp: stamp, cross_validation_stamps: cross_validation_stamps}

      assert false ==
               Replication.valid_transaction?(tx,
                 context: %Context{
                   previous_chain: [
                     %{
                       Transaction.new(:node, %TransactionData{})
                       | validation_stamp: %ValidationStamp{
                           proof_of_integrity: :crypto.strong_rand_bytes(32),
                           proof_of_work: :crypto.strong_rand_bytes(32),
                           ledger_operations: %LedgerOperations{},
                           signature: ""
                         }
                     }
                   ]
                 }
               )
    end

    test "should return false when the ledger operations are invalid" do
      tx = Transaction.new(:node, %TransactionData{})

      P2P.add_node(%Node{
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key(),
        ip: {127, 0, 0, 1},
        port: 3000,
        ready?: true
      })

      stamp = %{
        proof_of_work: Crypto.node_public_key(),
        proof_of_integrity: Crypto.hash(tx),
        ledger_operations: %LedgerOperations{
          fee: 0.0,
          node_movements: [
            %Movement{to: :crypto.strong_rand_bytes(32), amount: 0.0},
            %Movement{to: Crypto.node_public_key(), amount: 0.0}
          ],
          unspent_outputs: [
            %UnspentOutput{
              amount: 10,
              from: tx.address
            }
          ]
        }
      }

      stamp =
        struct!(ValidationStamp, Map.put(stamp, :signature, Crypto.sign_with_node_key(stamp)))

      cross_validation_stamps = [
        CrossValidationStamp.new(stamp, [])
      ]

      tx = %{tx | validation_stamp: stamp, cross_validation_stamps: cross_validation_stamps}
      assert false == Replication.valid_transaction?(tx, context: %Context{})
    end
  end

  test "run/1 should validate transaction, store it and notify the beacon chain" do
    start_supervised!({BeaconSlotTimer, interval: 0, trigger_offset: 0})
    Enum.each(BeaconSubsets.all(), &BeaconSubset.start_link(subset: &1))

    P2P.add_node(%Node{
      first_public_key: Crypto.node_public_key(),
      last_public_key: Crypto.node_public_key(),
      ip: {127, 0, 0, 1},
      port: 3000,
      ready?: true,
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    {pub, pv} = Crypto.generate_deterministic_keypair("seed")

    P2P.add_node(%Node{
      first_public_key: pub,
      last_public_key: pub,
      ip: {127, 0, 0, 1},
      port: 3000,
      ready?: true,
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    tx = Transaction.new(:node, %TransactionData{})

    validation_stamp =
      ValidationStamp.new(tx, %Context{}, "welcome_node_public_key", Crypto.node_public_key(), [
        pub
      ])

    cross_validation_stamps = [
      CrossValidationStamp.new(validation_stamp, []),
      %CrossValidationStamp{
        signature: Crypto.sign(validation_stamp, pv),
        node_public_key: pub,
        inconsistencies: []
      }
    ]

    validated_tx = %{
      tx
      | validation_stamp: validation_stamp,
        cross_validation_stamps: cross_validation_stamps
    }

    me = self()

    MockStorage
    |> expect(:write_transaction_chain, fn _ ->
      send(me, :replicated)
      :ok
    end)

    MockNodeClient
    |> stub(:send_message, fn _, _, msg ->
      case msg do
        {:get_unspent_outputs, _} ->
          []
      end
    end)

    Replication.run(validated_tx)

    Process.sleep(200)

    assert_received :replicated

    subset = Beacon.subset_from_address(tx.address)
    [{pid, _}] = Registry.lookup(BeaconSubsetRegistry, subset)

    assert %{
             current_slot: %{
               transactions: [
                 %TransactionInfo{}
               ]
             }
           } = :sys.get_state(pid)
  end
end
