defmodule Uniris.Storage.Memory.UCOLedgerTest do
  use ExUnit.Case

  alias Uniris.Crypto

  alias Uniris.Storage.Memory.UCOLedger

  alias Uniris.Transaction
  alias Uniris.Transaction.ValidationStamp
  alias Uniris.Transaction.ValidationStamp.LedgerOperations
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.NodeMovement
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.TransactionMovement
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  import Mox

  setup :set_mox_global

  test "get_unspent_outputs/1 should return the non spent inputs" do
    UCOLedger.start_link([])

    UCOLedger.distribute_unspent_outputs(%Transaction{
      address: "@Charlie3",
      previous_public_key: "Charlie2",
      validation_stamp: %ValidationStamp{
        ledger_operations: %LedgerOperations{
          unspent_outputs: [
            %UnspentOutput{
              from: "@Alice2",
              amount: 2.0
            }
          ]
        }
      }
    })

    assert [
             %UnspentOutput{
               from: "@Alice2",
               amount: 2.0
             }
           ] = UCOLedger.get_unspent_outputs("@Charlie3")
  end

  test "balance/1 should return the balance of an address" do
    UCOLedger.start_link([])

    UCOLedger.distribute_unspent_outputs(%Transaction{
      address: "@Charlie3",
      previous_public_key: "Charlie2",
      validation_stamp: %ValidationStamp{
        ledger_operations: %LedgerOperations{
          unspent_outputs: [
            %UnspentOutput{
              from: "@Alice2",
              amount: 2.0
            }
          ]
        }
      }
    })

    assert 2.0 = UCOLedger.balance("@Charlie3")
  end

  test "start_link/1 should create ets table and load transactions and distribute funds memory" do
    MockStorage
    |> stub(:list_transactions, fn _fields ->
      [
        %Transaction{
          address: "@Alice2",
          previous_public_key: "Alice1",
          validation_stamp: %ValidationStamp{
            ledger_operations: %LedgerOperations{
              unspent_outputs: [
                %UnspentOutput{
                  from: "@Bob3",
                  amount: 5.0
                }
              ],
              transaction_movements: [
                %TransactionMovement{
                  to: "@Charlie3",
                  amount: 2.0
                }
              ],
              node_movements: [
                %NodeMovement{
                  to: "Node2",
                  amount: 0.30
                }
              ]
            }
          }
        }
      ]
    end)

    UCOLedger.start_link([])

    assert [%UnspentOutput{from: "@Bob3", amount: 5.0}] = UCOLedger.get_unspent_outputs("@Alice2")

    assert [%UnspentOutput{from: "@Alice2", amount: 0.3}] =
             UCOLedger.get_unspent_outputs(Crypto.hash("Node2"))

    assert [%UnspentOutput{from: "@Alice2", amount: 2.0}] =
             UCOLedger.get_unspent_outputs("@Charlie3")
  end
end
