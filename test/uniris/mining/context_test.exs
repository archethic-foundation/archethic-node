defmodule Uniris.Mining.ContextTest do
  use UnirisCase, async: false

  alias Uniris.BeaconSlotTimer
  alias Uniris.Crypto

  alias Uniris.Mining.Context

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetProofOfIntegrity
  alias Uniris.P2P.Message.GetTransaction
  alias Uniris.P2P.Message.GetTransactionHistory
  alias Uniris.P2P.Message.GetUnspentOutputs
  alias Uniris.P2P.Message.ProofOfIntegrity
  alias Uniris.P2P.Message.TransactionHistory
  alias Uniris.P2P.Message.UnspentOutputList
  alias Uniris.P2P.Node

  alias Uniris.Transaction
  alias Uniris.Transaction.ValidationStamp
  alias Uniris.Transaction.ValidationStamp.LedgerOperations
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Uniris.TransactionData
  alias Uniris.TransactionData.Ledger
  alias Uniris.TransactionData.Ledger.Transfer
  alias Uniris.TransactionData.UCOLedger

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    start_supervised!({BeaconSlotTimer, interval: 0, trigger_offset: 0})

    P2P.add_node(%Node{
      first_public_key: "key0",
      last_public_key: "key0",
      ip: {127, 0, 0, 1},
      port: 3000,
      ready?: true,
      geo_patch: "AAA",
      network_patch: "AAA",
      authorized?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-3600, :second)
    })

    P2P.add_node(%Node{
      last_public_key: "key1",
      first_public_key: "key1",
      network_patch: "AA0",
      ip: {88, 100, 200, 15},
      port: 3000,
      average_availability: 1,
      available?: true,
      geo_patch: "AAC",
      ready?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-8000, :second)
    })

    P2P.add_node(%Node{
      last_public_key: "key2",
      first_public_key: "key2",
      network_patch: "AAA",
      ip: {150, 10, 20, 32},
      port: 3000,
      average_availability: 1,
      available?: true,
      geo_patch: "AAA",
      ready?: true
    })

    :ok
  end

  test "compute_p2p_view/2 should create a context and define views in bitstring" do
    chain_storage_nodes = [
      %Node{
        first_public_key: "key0",
        last_public_key: "key0",
        ip: {127, 0, 0, 1},
        port: 4000,
        available?: true
      },
      %Node{
        first_public_key: "key1",
        last_public_key: "key1",
        ip: {127, 0, 0, 1},
        port: 4000,
        available?: true
      },
      %Node{
        first_public_key: "key2",
        last_public_key: "key2",
        ip: {127, 0, 0, 1},
        port: 4000,
        available?: true
      }
    ]

    beacon_storage_nodes = [
      %Node{
        first_public_key: "key0",
        last_public_key: "key0",
        ip: {127, 0, 0, 1},
        port: 4000,
        available?: true
      },
      %Node{
        first_public_key: "key1",
        last_public_key: "key1",
        ip: {127, 0, 0, 1},
        port: 4002,
        available?: true
      }
    ]

    cross_validation_nodes = [
      %Node{
        last_public_key: "v1",
        first_public_key: "v1",
        ip: {127, 0, 0, 1},
        port: 3000,
        available?: true
      },
      %Node{
        last_public_key: "v2",
        first_public_key: "v2",
        ip: {127, 0, 0, 1},
        port: 3045,
        available?: true
      }
    ]

    assert %Context{
             cross_validation_nodes_view: <<1::1, 1::1>>,
             beacon_storage_nodes_view: <<1::1, 1::1>>,
             chain_storage_nodes_view: <<1::1, 1::1, 1::1>>
           } =
             Context.compute_p2p_view(
               %Context{},
               cross_validation_nodes,
               chain_storage_nodes,
               beacon_storage_nodes
             )
  end

  test "aggregate/2 should aggregate context views and involved_nodes" do
    context1 = %Context{
      cross_validation_nodes_view: <<1::1, 1::1, 1::1>>,
      beacon_storage_nodes_view: <<1::1, 1::1>>,
      chain_storage_nodes_view: <<1::1, 1::1, 1::1>>,
      involved_nodes: [
        "key0",
        "key1",
        "key2"
      ]
    }

    context2 = %Context{
      cross_validation_nodes_view: <<1::1, 1::1, 0::1>>,
      beacon_storage_nodes_view: <<0::1, 1::1>>,
      chain_storage_nodes_view: <<1::1, 0::1, 1::1>>,
      involved_nodes: [
        "key2",
        "key4",
        "key1"
      ]
    }

    assert %Context{
             involved_nodes: [
               "key0",
               "key1",
               "key2",
               "key4"
             ],
             cross_validation_nodes_view: <<1::1, 1::1, 1::1>>,
             beacon_storage_nodes_view: <<1::1, 1::1>>,
             chain_storage_nodes_view: <<1::1, 1::1, 1::1>>
           } = Context.aggregate(context1, context2)
  end

  describe "fetch_history/2" do
    test "should retrieved transaction chain locally and fetch unspent outputs while performs confirmation" do
      P2P.add_node(%Node{
        first_public_key: Crypto.node_public_key(0),
        last_public_key: Crypto.node_public_key(0),
        ip: {127, 0, 0, 1},
        port: 4000,
        network_patch: "AAA"
      })

      tx1 = Transaction.new(:node, %TransactionData{}, "node_seed", 0)

      tx1 = %{
        tx1
        | validation_stamp: %ValidationStamp{
            ledger_operations: %LedgerOperations{},
            proof_of_integrity: :crypto.strong_rand_bytes(32),
            proof_of_work: :crypto.strong_rand_bytes(32),
            signature: :crypto.strong_rand_bytes(64)
          }
      }

      tx2 = Transaction.new(:node, %TransactionData{}, "node_seed", 1)

      MockNodeClient
      |> stub(:send_message, fn _, _, msg ->
        case msg do
          %GetTransaction{} ->
            utxo =
              Transaction.new(
                :transfer,
                %TransactionData{
                  ledger: %Ledger{
                    uco: %UCOLedger{
                      transfers: [
                        %Transfer{to: tx1.address, amount: 10}
                      ]
                    }
                  }
                },
                "seed",
                0
              )

            utxo = %{
              utxo
              | validation_stamp: %ValidationStamp{
                  proof_of_integrity: "",
                  proof_of_work: "",
                  ledger_operations: %LedgerOperations{},
                  signature: ""
                }
            }

            utxo

          %GetUnspentOutputs{} ->
            %UnspentOutputList{
              unspent_outputs: [
                %UnspentOutput{from: :crypto.strong_rand_bytes(32), amount: 10}
              ]
            }

          %GetProofOfIntegrity{} ->
            %ProofOfIntegrity{
              digest: tx1.validation_stamp.proof_of_integrity
            }
        end
      end)

      MockStorage
      |> expect(:get_transaction_chain, fn _ ->
        [tx1]
      end)

      assert %Context{
               previous_chain: [tx1],
               unspent_outputs: [%UnspentOutput{amount: 10}]
             } = Context.fetch_history(%Context{}, tx2)
    end

    test "should retrieved transaction chain, unspent outputs and performs confirmation" do
      P2P.add_node(%Node{
        first_public_key: Crypto.node_public_key(0),
        last_public_key: Crypto.node_public_key(0),
        ip: {127, 0, 0, 1},
        port: 4000,
        network_patch: "AAA"
      })

      tx1 = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      tx1 = %{
        tx1
        | validation_stamp: %ValidationStamp{
            ledger_operations: %LedgerOperations{},
            proof_of_integrity: :crypto.strong_rand_bytes(32),
            proof_of_work: :crypto.strong_rand_bytes(32),
            signature: :crypto.strong_rand_bytes(64)
          }
      }

      tx2 = Transaction.new(:transfer, %TransactionData{}, "seed", 1)

      utxo =
        Transaction.new(
          :transfer,
          %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: [
                  %Transfer{to: tx1.address, amount: 10}
                ]
              }
            }
          },
          "utxo_seed",
          0
        )

      utxo = %{
        utxo
        | validation_stamp: %ValidationStamp{
            proof_of_integrity: "",
            proof_of_work: "",
            ledger_operations: %LedgerOperations{},
            signature: ""
          }
      }

      MockNodeClient
      |> stub(:send_message, fn _, _, msg ->
        case msg do
          %GetTransactionHistory{} ->
            %TransactionHistory{
              transaction_chain: [tx1],
              unspent_outputs: [%UnspentOutput{from: utxo.address, amount: 10}]
            }

          %GetTransaction{} ->
            utxo

          %GetProofOfIntegrity{} ->
            %ProofOfIntegrity{
              digest: tx1.validation_stamp.proof_of_integrity
            }
        end
      end)

      assert %Context{
               previous_chain: [tx1],
               unspent_outputs: [%UnspentOutput{amount: 10}]
             } = Context.fetch_history(%Context{}, tx2)
    end

    test "should retrieved transaction chain and performs confirmation" do
      P2P.add_node(%Node{
        first_public_key: Crypto.node_public_key(0),
        last_public_key: Crypto.node_public_key(0),
        ip: {127, 0, 0, 1},
        port: 4000,
        network_patch: "AAA"
      })

      tx1 = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      tx1 = %{
        tx1
        | validation_stamp: %ValidationStamp{
            ledger_operations: %LedgerOperations{},
            proof_of_integrity: :crypto.strong_rand_bytes(32),
            proof_of_work: :crypto.strong_rand_bytes(32),
            signature: :crypto.strong_rand_bytes(64)
          }
      }

      tx2 = Transaction.new(:transfer, %TransactionData{}, "seed", 1)

      MockNodeClient
      |> stub(:send_message, fn _, _, msg ->
        case msg do
          %GetTransactionHistory{} ->
            %TransactionHistory{
              transaction_chain: [tx1],
              unspent_outputs: []
            }

          %GetProofOfIntegrity{} ->
            %ProofOfIntegrity{
              digest: tx1.validation_stamp.proof_of_integrity
            }
        end
      end)

      assert %Context{
               previous_chain: [tx1],
               unspent_outputs: []
             } = Context.fetch_history(%Context{}, tx2)
    end
  end
end
