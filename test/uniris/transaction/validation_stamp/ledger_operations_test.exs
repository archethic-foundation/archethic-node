defmodule Uniris.Transaction.ValidationStamp.LedgerOperationsTest do
  use UnirisCase
  use ExUnitProperties

  alias Uniris.Transaction
  alias Uniris.Transaction.ValidationStamp.LedgerOperations
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.NodeMovement
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.TransactionMovement
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Uniris.TransactionData
  alias Uniris.TransactionData.Ledger
  alias Uniris.TransactionData.Ledger.Transfer
  alias Uniris.TransactionData.UCOLedger

  doctest LedgerOperations

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

      utxos = [%UnspentOutput{from: tx.address, amount: 1.1}]

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
                 %TransactionMovement{
                   to: Enum.at(tx.data.ledger.uco.transfers, 0).to,
                   amount: 2.2
                 },
                 %TransactionMovement{
                   to: Enum.at(tx.data.ledger.uco.transfers, 1).to,
                   amount: 4.2
                 }
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
          %NodeMovement{to: "node1", amount: 10}
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
          %NodeMovement{to: "node1", amount: 10}
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
          %NodeMovement{to: "node1", amount: 10}
        ],
        transaction_movements: [
          %TransactionMovement{to: tx.address, amount: 1000}
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
          %NodeMovement{to: "node1", amount: 10}
        ],
        unspent_outputs: []
      }

      assert false == LedgerOperations.verify?(ops, tx, utxo, [])
    end

    test "should return an error when the node movements are present without fee" do
      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      utxo = [%UnspentOutput{from: tx.address, amount: 10}]

      ops = %LedgerOperations{
        fee: 0.0,
        node_movements: [
          %NodeMovement{to: "node1", amount: 10}
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
          %NodeMovement{to: "welcome_node1", amount: 0.0},
          %NodeMovement{to: "node_1", amount: 0.0},
          %NodeMovement{to: "other_cross_validator", amount: 0.0},
          %NodeMovement{to: "other_cross_validator", amount: 0.0}
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
          %NodeMovement{to: "welcome_node1", amount: 0.0},
          %NodeMovement{to: "node_1", amount: 10.0},
          %NodeMovement{to: "cross_validator_1", amount: 5.0},
          %NodeMovement{to: "cross_validator_2", amount: 6.0}
        ],
        unspent_outputs: [%UnspentOutput{from: tx.address, amount: 10}]
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
          %NodeMovement{to: :crypto.strong_rand_bytes(32), amount: 0.0005},
          %NodeMovement{to: "coordinator1", amount: 0.026166666666666668},
          %NodeMovement{to: "cross_validator_1", amount: 0.03666666666666667},
          %NodeMovement{to: "cross_validator_2", amount: 0.03666666666666667}
        ],
        transaction_movements: [
          %TransactionMovement{to: "@Alice2", amount: 5.0}
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

  property "symmetric serialization/deserialization of ledger operations" do
    check all(
            fee <- StreamData.float(min: 0.0),
            transaction_movements <-
              StreamData.map_of(StreamData.binary(length: 32), StreamData.float(min: 0.0)),
            node_movements <-
              StreamData.map_of(StreamData.binary(length: 32), StreamData.float(min: 0.0)),
            unspent_outputs <-
              StreamData.map_of(StreamData.binary(length: 32), StreamData.float(min: 0.0))
          ) do
      transaction_movements =
        Enum.map(transaction_movements, fn {to, amount} ->
          %TransactionMovement{
            to: <<0::8>> <> to,
            amount: amount
          }
        end)

      node_movements =
        Enum.map(node_movements, fn {to, amount} ->
          %NodeMovement{
            to: <<0::8>> <> to,
            amount: amount
          }
        end)

      unspent_outputs =
        Enum.map(unspent_outputs, fn {from, amount} ->
          %UnspentOutput{
            from: <<0::8>> <> from,
            amount: amount
          }
        end)

      {ledger_ops, _} =
        %LedgerOperations{
          fee: fee,
          transaction_movements: transaction_movements,
          node_movements: node_movements,
          unspent_outputs: unspent_outputs
        }
        |> LedgerOperations.serialize()
        |> LedgerOperations.deserialize()

      assert ledger_ops.fee == fee
      assert ledger_ops.transaction_movements == transaction_movements
      assert ledger_ops.node_movements == node_movements
      assert ledger_ops.unspent_outputs == unspent_outputs
    end
  end
end
