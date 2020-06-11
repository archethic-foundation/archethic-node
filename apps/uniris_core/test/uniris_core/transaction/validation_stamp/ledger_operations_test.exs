defmodule UnirisCore.Transaction.ValidationStamp.LedgerOperationsTest do
  use UnirisCoreCase

  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.TransactionData.Ledger
  alias UnirisCore.TransactionData.Ledger.Transfer
  alias UnirisCore.TransactionData.UCOLedger
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations.Movement
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  describe "new!/4" do
    test "return an error when transaction use transfers and no unspent outputs transactions to use" do
      fee = 0.35

      tx =
        Transaction.new(
          :transfer,
          %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: [
                  %Transfer{to: :crypto.strong_rand_bytes(32), amount: 2.2},
                  %Transfer{to: :crypto.strong_rand_bytes(32), amount: 4.2}
                ]
              }
            }
          },
          :crypto.strong_rand_bytes(32),
          0
        )

      assert_raise RuntimeError, "Unsufficient funds for #{Base.encode16(tx.address)}", fn ->
        LedgerOperations.new!(tx, fee, [], [])
      end
    end

    test "return an error when transaction without transfers and no unspent outputs transactions to use (only fee to pay)" do
      fee = 0.35

      tx = Transaction.new(:transfer, %TransactionData{}, :crypto.strong_rand_bytes(32), 0)

      assert_raise RuntimeError, "Unsufficient funds for #{Base.encode16(tx.address)}", fn ->
        LedgerOperations.new!(tx, fee, [], [])
      end
    end

    test "return an error when not enought unspent outputs transactions to use" do
      fee = 0.35

      tx =
        Transaction.new(
          :transfer,
          %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: [
                  %Transfer{to: :crypto.strong_rand_bytes(32), amount: 2.2},
                  %Transfer{to: :crypto.strong_rand_bytes(32), amount: 4.2}
                ]
              }
            }
          },
          :crypto.strong_rand_bytes(32),
          0
        )

      utxos = [%Movement{to: tx.address, amount: 1.1}]

      assert_raise RuntimeError, "Unsufficient funds for #{Base.encode16(tx.address)}", fn ->
        LedgerOperations.new!(tx, fee, utxos, [])
      end
    end

    test "return an error when enought utxo for transfer but not for the fees" do
      fee = 0.35

      tx =
        Transaction.new(
          :transfer,
          %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: [
                  %Transfer{to: :crypto.strong_rand_bytes(32), amount: 2.2},
                  %Transfer{to: :crypto.strong_rand_bytes(32), amount: 4.2}
                ]
              }
            }
          },
          :crypto.strong_rand_bytes(32),
          0
        )

      utxos = [%UnspentOutput{amount: 6.4, from: :crypto.strong_rand_bytes(32)}]

      assert_raise RuntimeError, "Unsufficient funds for #{Base.encode16(tx.address)}", fn ->
        LedgerOperations.new!(tx, fee, utxos, [])
      end
    end

    test "return ledger operations with remaining utxo and ledger movements when enough funds" do
      fee = 0.35

      tx =
        Transaction.new(
          :transfer,
          %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: [
                  %Transfer{to: :crypto.strong_rand_bytes(32), amount: 2.2},
                  %Transfer{to: :crypto.strong_rand_bytes(32), amount: 4.2}
                ]
              }
            }
          },
          :crypto.strong_rand_bytes(32),
          0
        )

      utxos = [
        %UnspentOutput{from: "@Alice2", amount: 3},
        %UnspentOutput{from: "@Bob5", amount: 5},
        %UnspentOutput{from: "@Tom4", amount: 7}
      ]

      assert %LedgerOperations{
               transaction_movements: [
                 %Movement{to: Enum.at(tx.data.ledger.uco.transfers, 0).to, amount: 2.2},
                 %Movement{to: Enum.at(tx.data.ledger.uco.transfers, 1).to, amount: 4.2}
               ],
               unspent_outputs: [
                 %UnspentOutput{from: tx.address, amount: 1.25},
                 %UnspentOutput{from: "@Tom4", amount: 7}
               ],
               fee: fee
             } == LedgerOperations.new!(tx, fee, utxos, [])
    end
  end

  describe "verify?/5" do
    test "should return false when the fee specified is invalid" do
      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      ops = %LedgerOperations{
        fee: 100,
        node_movements: [
          %Movement{to: "node1", amount: 10}
        ]
      }

      assert false == LedgerOperations.verify?(ops, tx, [], [])
    end

    test "should return an error when there are unsufficients funds" do
      tx =
        Transaction.new(
          :transfer,
          %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: [
                  %Transfer{to: :crypto.strong_rand_bytes(32), amount: 10}
                ]
              }
            }
          },
          "seed",
          0
        )

      utxo = [%UnspentOutput{from: :crypto.strong_rand_bytes(32), amount: 2}]

      ops = %LedgerOperations{
        # TODO: use the right one when the algo is implemented
        fee: 0.1,
        node_movements: [
          %Movement{to: "node1", amount: 10}
        ]
      }

      assert false == LedgerOperations.verify?(ops, tx, utxo, [])
    end

    test "should return an error when the transaction movements are differents" do
      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      utxo = [%UnspentOutput{from: tx.address, amount: 10}]

      ops = %LedgerOperations{
        # TODO: use the right one when the algo is implemented
        fee: 0.1,
        node_movements: [
          %Movement{to: "node1", amount: 10}
        ],
        transaction_movements: [
          %Movement{to: tx.address, amount: 1000}
        ]
      }

      assert false == LedgerOperations.verify?(ops, tx, utxo, [])
    end

    test "should return an error when the unspent output transactions are differents" do
      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      utxo = [%UnspentOutput{from: tx.address, amount: 10}]

      ops = %LedgerOperations{
        # TODO: use the right one when the algo is implemented
        fee: 0.1,
        node_movements: [
          %Movement{to: "node1", amount: 10}
        ],
        unspent_outputs: []
      }

      assert false == LedgerOperations.verify?(ops, tx, utxo, [])
    end

    test "should return an error when the node movements are present without fee" do
      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      utxo = [%Movement{to: tx.address, amount: 10}]

      ops = %LedgerOperations{
        fee: 0.0,
        node_movements: [
          %Movement{to: "node1", amount: 10}
        ],
        unspent_outputs: [%UnspentOutput{from: :crypto.strong_rand_bytes(32), amount: 10}]
      }

      assert false == LedgerOperations.verify?(ops, tx, utxo, [])
    end

    test "should return an error when the rewarded nodes are not the expected ones" do
      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      utxo = [%UnspentOutput{from: :crypto.strong_rand_bytes(32), amount: 10}]

      ops = %LedgerOperations{
        # TODO: use the right one when the algo is implemented
        fee: 0.1,
        node_movements: [
          %Movement{to: "welcome_node1", amount: 0.0},
          %Movement{to: "node_1", amount: 0.0},
          %Movement{to: "other_cross_validator", amount: 0.0},
          %Movement{to: "other_cross_validator", amount: 0.0}
        ],
        unspent_outputs: [
          %UnspentOutput{from: tx.address, amount: 10}
        ]
      }

      assert false ==
               LedgerOperations.verify?(ops, tx, utxo, [
                 "coordinator1",
                 "cross_validator_1",
                 "cross_validator_2"
               ])
    end

    test "should return an error when the rewards are invalid" do
      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      utxo = [%UnspentOutput{from: :crypto.strong_rand_bytes(32), amount: 10}]

      ops = %LedgerOperations{
        # TODO: use the right one when the algo is implemented
        fee: 0.1,
        node_movements: [
          %Movement{to: "welcome_node1", amount: 0.0},
          %Movement{to: "node_1", amount: 10.0},
          %Movement{to: "cross_validator_1", amount: 5.0},
          %Movement{to: "cross_validator_2", amount: 6.0}
        ],
        unspent_outputs: [%Movement{to: tx.address, amount: 10}]
      }

      assert false ==
               LedgerOperations.verify?(
                 ops,
                 tx,
                 utxo,
                 ["coordinator1", "cross_validator_1", "cross_validator_2"]
               )
    end

    test "should return true" do
      tx =
        Transaction.new(
          :transfer,
          %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: [
                  %Transfer{to: "@Alice2", amount: 5.0}
                ]
              }
            }
          },
          "seed",
          0
        )

      utxo = [%UnspentOutput{from: :crypto.strong_rand_bytes(32), amount: 15}]

      ops = %LedgerOperations{
        # TODO: use the right one when the algo is implemented
        fee: 0.1,
        node_movements: [
          %Movement{to: :crypto.strong_rand_bytes(32), amount: 0.0005},
          %Movement{to: "coordinator1", amount: 0.026166666666666668},
          %Movement{to: "cross_validator_1", amount: 0.03666666666666667},
          %Movement{to: "cross_validator_2", amount: 0.03666666666666667}
        ],
        transaction_movements: [
          %Movement{to: "@Alice2", amount: 5.0}
        ],
        unspent_outputs: [
          %UnspentOutput{from: tx.address, amount: 9.9}
        ]
      }

      assert LedgerOperations.verify?(ops, tx, utxo, [
               "coordinator1",
               "cross_validator_1",
               "cross_validator_2"
             ])
    end
  end
end
