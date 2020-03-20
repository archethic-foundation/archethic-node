defmodule UnirisValidation.DefaultImpl.ReplicationTest do
  use ExUnit.Case
  doctest UnirisValidation.DefaultImpl.Replication

  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.Data
  alias UnirisChain.Transaction.Data.Ledger
  alias UnirisChain.Transaction.Data.Ledger.UCO
  alias UnirisChain.Transaction.Data.Ledger.Transfer
  alias UnirisChain.Transaction.ValidationStamp
  alias UnirisChain.Transaction.ValidationStamp.NodeMovements
  alias UnirisChain.Transaction.ValidationStamp.LedgerMovements
  alias UnirisChain.Transaction.ValidationStamp.LedgerMovements.UTXO
  alias UnirisCrypto, as: Crypto
  alias UnirisValidation.DefaultImpl.Replication
  alias UnirisValidation.DefaultImpl.ProofOfIntegrity
  alias UnirisValidation.DefaultImpl.ProofOfWork
  alias UnirisValidation.DefaultImpl.Reward
  alias UnirisValidation.DefaultImpl.Fee
  alias UnirisP2P.Node

  import Mox

  setup :verify_on_exit!

  setup do
    Crypto.add_origin_seed("first_seed")
    MockSharedSecrets |> stub(:origin_public_keys, fn _ -> Crypto.origin_public_keys() end)
    :ok
  end

  test "full_validation/1 should performs a full check (chain integrity, context building, transaction validation)" do
    tx =
      Transaction.from_seed("seed", :transfer, %Data{
        ledger: %Ledger{
          uco: %UCO{
            transfers: [
              %Transfer{to: :crypto.strong_rand_bytes(32), amount: 10}
            ]
          }
        }
      })

    unspent_outputs = [
      %Transaction{
        address: :crypto.strong_rand_bytes(32),
        type: :transfer,
        timestamp: DateTime.utc_now(),
        data: %{
          ledger: %{
            uco: %{
              transfers: [
                %{to: tx.address, amount: 11}
              ]
            }
          }
        },
        previous_public_key: "",
        previous_signature: "",
        origin_signature: ""
      }
    ]

    previous_tx = %Transaction{
      address: Crypto.hash(tx.previous_public_key),
      type: :transfer,
      timestamp: DateTime.utc_now(),
      data: %{},
      previous_public_key: "",
      previous_signature: "",
      origin_signature: ""
    }

    previous_tx = %{
      previous_tx
      | validation_stamp: %ValidationStamp{
          proof_of_work: :crypto.strong_rand_bytes(32),
          proof_of_integrity: ProofOfIntegrity.from_transaction(previous_tx),
          ledger_movements: %LedgerMovements{uco: %UTXO{}},
          node_movements: %NodeMovements{fee: 1, rewards: []},
          signature: ""
        }
    }

    previous_chain = [previous_tx]

    MockP2P
    |> stub(:node_info, fn _ ->
      {:ok,
       %Node{
         first_public_key: "node",
         last_public_key: "node",
         availability: 1,
         network_patch: "ADA",
         average_availability: 1,
         ip: "",
         port: 3000,
         geo_patch: ""
       }}
    end)
    |> stub(:send_message, fn _, msg ->
      case msg do
        [{:get_transaction_chain, _}, {:get_unspent_outputs, _}] ->
          [{:ok, previous_chain}, {:ok, unspent_outputs}]
      end
    end)

    coordinator_pub = Crypto.node_public_key()

    MockElection
    |> stub(:storage_nodes, fn _, _ ->
      [
        %Node{
          last_public_key: "storage_node_key1",
          availability: 1,
          network_patch: "AFA",
          first_public_key: "storage_node_key1",
          ip: "",
          port: 3000,
          geo_patch: "",
          average_availability: 1
        },
        %Node{
          last_public_key: "storage_node_key2",
          first_public_key: "storage_node_key2",
          availability: 1,
          network_patch: "DCA",
          average_availability: 1,
          ip: "",
          port: 3000,
          geo_patch: ""
        }
      ]
    end)
    |> expect(:validation_nodes, fn _ ->
      [
        %Node{
          first_public_key: coordinator_pub,
          last_public_key: coordinator_pub,
          availability: 1,
          network_patch: "ACA",
          geo_patch: "",
          average_availability: 1,
          ip: "",
          port: 3000
        },
        %Node{
          first_public_key: "validator_key2",
          last_public_key: "validator_key2",
          availability: 1,
          network_patch: "ADA",
          ip: "",
          port: 3000,
          average_availability: 1,
          geo_patch: "AAA"
        }
      ]
    end)

    {:ok, pow} = ProofOfWork.run(tx)
    poi = ProofOfIntegrity.from_chain([tx | previous_chain])
    fee = Fee.from_transaction(tx)

    node_movements = %NodeMovements{
      fee: fee,
      rewards:
        Reward.distribute_fee(fee, "welcome_node_key", coordinator_pub, ["validator_key2"], [
          "storage_node_key1",
          "storage_node_key2"
        ])
    }

    ledger_movements = %LedgerMovements{
      uco: %UTXO{
        previous: %{from: [List.first(unspent_outputs).address], amount: 11},
        next: 0.9000000000000004
      }
    }

    stamp = ValidationStamp.new(pow, poi, ledger_movements, node_movements)

    sig = Crypto.sign_with_node_key(stamp)

    validated_tx = %{
      tx
      | validation_stamp: stamp,
        cross_validation_stamps: [{sig, [], Crypto.node_public_key()}]
    }

    assert {:ok, [validated_tx | previous_chain]} = Replication.full_validation(validated_tx)
  end

  test "lite_validation/1 should validate the transaction only with cryptographic checks" do
    tx =
      Transaction.from_seed("seed", :transfer, %Data{
        ledger: %Ledger{
          uco: %UCO{
            transfers: [
              %Transfer{to: :crypto.strong_rand_bytes(32), amount: 10}
            ]
          }
        }
      })

    {:ok, pow} = ProofOfWork.run(tx)
    poi = ProofOfIntegrity.from_chain([tx])
    fee = Fee.from_transaction(tx)

    coordinator_pub = Crypto.node_public_key()

    node_movements = %NodeMovements{
      fee: fee,
      rewards:
        Reward.distribute_fee(fee, "welcome_node_key", coordinator_pub, ["validator_key2"], [
          "storage_node_key1",
          "storage_node_key2"
        ])
    }

    ledger_movements = %LedgerMovements{
      uco: %UTXO{
        previous: %{from: [], amount: 11},
        next: 0.9000000000000004
      }
    }

    stamp = ValidationStamp.new(pow, poi, ledger_movements, node_movements)

    sig = Crypto.sign_with_node_key(stamp)

    validated_tx = %{
      tx
      | validation_stamp: stamp,
        cross_validation_stamps: [{sig, [], Crypto.node_public_key()}]
    }

    assert :ok = Replication.lite_validation(validated_tx)
  end
end
