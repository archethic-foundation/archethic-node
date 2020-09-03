defmodule Uniris.Mining.ReplicationTest do
  use UnirisCase, async: false
  doctest Uniris.Mining.Replication

  @moduletag capture_log: true

  alias Uniris.Crypto

  alias Uniris.Beacon
  alias Uniris.BeaconSlot.TransactionInfo
  alias Uniris.BeaconSlotTimer
  alias Uniris.BeaconSubset
  alias Uniris.BeaconSubsetRegistry

  alias Uniris.Mining.Context
  alias Uniris.Mining.ProofOfIntegrity
  alias Uniris.Mining.Replication

  alias Uniris.P2P.Message.GetUnspentOutputs
  alias Uniris.P2P.Message.UnspentOutputList
  alias Uniris.P2P.Node

  alias Uniris.Storage.Memory.NetworkLedger

  alias Uniris.Transaction
  alias Uniris.Transaction.CrossValidationStamp
  alias Uniris.Transaction.ValidationStamp
  alias Uniris.Transaction.ValidationStamp.LedgerOperations
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.NodeMovement
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Uniris.TransactionData

  import Mox

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
            %NodeMovement{to: :crypto.strong_rand_bytes(32), amount: 0.0},
            %NodeMovement{to: Crypto.node_public_key(), amount: 0.0}
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

      stamp = %ValidationStamp{
        proof_of_work: <<0>> <> :crypto.strong_rand_bytes(32),
        proof_of_integrity: :crypto.strong_rand_bytes(32),
        ledger_operations: %LedgerOperations{
          node_movements: [
            %NodeMovement{to: :crypto.strong_rand_bytes(32), amount: 0.0},
            %NodeMovement{to: Crypto.node_public_key(), amount: 0.0}
          ]
        }
      }

      sig =
        stamp
        |> ValidationStamp.serialize()
        |> Crypto.sign_with_node_key()

      cross_validation_stamps = [CrossValidationStamp.new(stamp, [])]

      tx = %{
        tx
        | validation_stamp: %{stamp | signature: sig},
          cross_validation_stamps: cross_validation_stamps
      }

      assert false == Replication.valid_transaction?(tx)
    end

    test "should return false when the fee is invalid" do
      tx = Transaction.new(:node, %TransactionData{})

      stamp = %ValidationStamp{
        proof_of_work: Crypto.node_public_key(0),
        proof_of_integrity: :crypto.strong_rand_bytes(32),
        ledger_operations: %LedgerOperations{
          fee: 5.5,
          node_movements: [
            %NodeMovement{to: :crypto.strong_rand_bytes(32), amount: 0.0},
            %NodeMovement{to: Crypto.node_public_key(), amount: 0.0}
          ]
        }
      }

      sig =
        stamp
        |> ValidationStamp.serialize()
        |> Crypto.sign_with_node_key()

      cross_validation_stamps = [CrossValidationStamp.new(stamp, [])]

      tx = %{
        tx
        | validation_stamp: %{stamp | signature: sig},
          cross_validation_stamps: cross_validation_stamps
      }

      assert false == Replication.valid_transaction?(tx)
    end

    test "should return false when the total rewards is invalid" do
      tx = Transaction.new(:node, %TransactionData{})

      stamp = %ValidationStamp{
        proof_of_work: Crypto.node_public_key(0),
        proof_of_integrity: :crypto.strong_rand_bytes(32),
        ledger_operations: %LedgerOperations{
          fee: 0.0,
          node_movements: [
            %NodeMovement{to: :crypto.strong_rand_bytes(32), amount: 1},
            %NodeMovement{to: Crypto.node_public_key(), amount: 3}
          ]
        }
      }

      sig =
        stamp
        |> ValidationStamp.serialize()
        |> Crypto.sign_with_node_key()

      cross_validation_stamps = [CrossValidationStamp.new(stamp, [])]

      tx = %{
        tx
        | validation_stamp: %{stamp | signature: sig},
          cross_validation_stamps: cross_validation_stamps
      }

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

      cross_validation_stamp_sig =
        stamp
        |> ValidationStamp.serialize()
        |> Crypto.sign(pv)

      cross_validation_stamps = [
        %CrossValidationStamp{
          signature: cross_validation_stamp_sig,
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

      NetworkLedger.add_node_info(%Node{
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key(),
        ip: {127, 0, 0, 1},
        port: 3000,
        ready?: true
      })

      stamp = %ValidationStamp{
        proof_of_work: Crypto.node_public_key(),
        proof_of_integrity: ProofOfIntegrity.compute([tx]),
        ledger_operations: %LedgerOperations{
          fee: 0.0,
          node_movements: [
            %NodeMovement{to: :crypto.strong_rand_bytes(32), amount: 0.0},
            %NodeMovement{to: Crypto.node_public_key(), amount: 0.0}
          ],
          unspent_outputs: [
            %UnspentOutput{
              amount: 10,
              from: tx.address
            }
          ]
        }
      }

      sig =
        stamp
        |> ValidationStamp.serialize()
        |> Crypto.sign_with_node_key()

      cross_validation_stamps = [
        CrossValidationStamp.new(stamp, [])
      ]

      tx = %{
        tx
        | validation_stamp: %{stamp | signature: sig},
          cross_validation_stamps: cross_validation_stamps
      }

      assert false == Replication.valid_transaction?(tx, context: %Context{})
    end
  end

  test "run/1 should validate transaction, store it and notify the beacon chain" do
    start_supervised!({BeaconSlotTimer, interval: "* * * * * *", trigger_offset: 0})
    Enum.each(Beacon.list_subsets(), &BeaconSubset.start_link(subset: &1))

    NetworkLedger.add_node_info(%Node{
      first_public_key: Crypto.node_public_key(),
      last_public_key: Crypto.node_public_key(),
      ip: {127, 0, 0, 1},
      port: 3000,
      ready?: true,
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now(),
      network_patch: "BBB"
    })

    {pub, pv} = Crypto.generate_deterministic_keypair("seed")

    NetworkLedger.add_node_info(%Node{
      first_public_key: pub,
      last_public_key: pub,
      ip: {127, 0, 0, 1},
      port: 3000,
      ready?: true,
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now(),
      network_patch: "AAA"
    })

    tx =
      Transaction.new(:node, %TransactionData{
        content: """
        ip: 127.0.0.1
        port: 3000
        """
      })

    validation_stamp =
      ValidationStamp.new(tx, %Context{}, "welcome_node_public_key", Crypto.node_public_key(), [
        pub
      ])

    cross_validation_stamp_sig =
      validation_stamp
      |> ValidationStamp.serialize()
      |> Crypto.sign(pv)

    cross_validation_stamps = [
      CrossValidationStamp.new(validation_stamp, []),
      %CrossValidationStamp{
        signature: cross_validation_stamp_sig,
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
        %GetUnspentOutputs{} ->
          {:ok, %UnspentOutputList{}}
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
