defmodule Archethic.Account.MemTables.GenesisInputLedgerTest do
  use ExUnit.Case

  alias Archethic.Account.MemTables.GenesisInputLedger

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.TransactionChain.TransactionInput

  setup do
    GenesisInputLedger.start_link()
    :ok
  end

  describe "add_chain_input/1" do
    test "should ingest a transaction and ingest the movements as input" do
      GenesisInputLedger.add_chain_input(
        %TransactionMovement{to: "@Bob3", amount: 100_000_000, type: :UCO},
        "@Alice2",
        ~U[2023-09-20 01:00:00Z],
        "@Bob0"
      )

      assert [
               %TransactionInput{
                 from: "@Alice2",
                 amount: 100_000_000,
                 type: :UCO,
                 timestamp: ~U[2023-09-20 01:00:00Z]
               }
             ] = GenesisInputLedger.get_unspent_inputs("@Bob0")
    end
  end

  describe "update_chain_inputs/2" do
    test "should ingest transaction UTXO reducing consumed inputs (with utxo consolidation)" do
      GenesisInputLedger.add_chain_input(
        %TransactionMovement{to: "@Alice5", amount: 200_000_000, type: :UCO},
        "@Bob3",
        ~U[2023-09-10 01:00:00Z],
        "@Alice0"
      )

      GenesisInputLedger.add_chain_input(
        %TransactionMovement{to: "@Alice5", amount: 200_000_000, type: :UCO},
        "@Tom5",
        ~U[2023-09-10 05:00:00Z],
        "@Alice0"
      )

      GenesisInputLedger.add_chain_input(
        %TransactionMovement{
          to: "@Alice5",
          amount: 100_000_000,
          type: {:token, "token1", 0}
        },
        "@Tom5",
        ~U[2023-09-10 05:00:00Z],
        "@Alice0"
      )

      tx = %Transaction{
        address: "@Alice2",
        validation_stamp: %ValidationStamp{
          timestamp: ~U[2023-09-20 01:00:00Z],
          ledger_operations: %LedgerOperations{
            consumed_inputs: [
              %UnspentOutput{
                from: "@Bob3",
                amount: 200_000_000,
                type: :UCO,
                timestamp: ~U[2023-09-10 01:00:00Z]
              },
              %UnspentOutput{
                from: "@Tom5",
                amount: 200_000_000,
                type: :UCO,
                timestamp: ~U[2023-09-10 05:00:00Z]
              },
              %UnspentOutput{
                from: "@Tom5",
                amount: 100_000_000,
                type: {:token, "token1", 0},
                timestamp: ~U[2023-09-10 05:00:00Z]
              }
            ],
            transaction_movements: [
              %TransactionMovement{to: "@Charlie10", amount: 100_000_000, type: :UCO}
            ],
            unspent_outputs: [
              %UnspentOutput{
                from: "@Alice2",
                type: :UCO,
                amount: 300_000_000,
                timestamp: ~U[2023-09-20 01:00:00Z]
              },
              %UnspentOutput{
                from: "@Alice2",
                amount: 100_000_000,
                type: {:token, "token1", 0},
                timestamp: ~U[2023-09-20 01:00:00Z]
              }
            ]
          }
        }
      }

      GenesisInputLedger.update_chain_inputs(tx, "@Alice0")

      assert [
               %TransactionInput{
                 from: "@Alice2",
                 amount: 300_000_000,
                 type: :UCO,
                 timestamp: ~U[2023-09-20 01:00:00Z]
               },
               %TransactionInput{
                 from: "@Alice2",
                 amount: 100_000_000,
                 type: {:token, "token1", 0},
                 timestamp: ~U[2023-09-20 01:00:00Z]
               }
             ] = GenesisInputLedger.get_unspent_inputs("@Alice0")
    end

    test "should ingest transaction UTXO reducing consumed inputs ((without utxo consolidation)" do
      GenesisInputLedger.add_chain_input(
        %TransactionMovement{to: "@Alice5", amount: 200_000_000, type: :UCO},
        "@Bob3",
        ~U[2023-09-10 01:00:00Z],
        "@Alice0"
      )

      GenesisInputLedger.add_chain_input(
        %TransactionMovement{to: "@Alice5", amount: 200_000_000, type: :UCO},
        "@Tom5",
        ~U[2023-09-10 05:00:00Z],
        "@Alice0"
      )

      GenesisInputLedger.add_chain_input(
        %TransactionMovement{
          to: "@Alice5",
          amount: 100_000_000,
          type: {:token, "token1", 0}
        },
        "@Tom5",
        ~U[2023-09-10 05:00:00Z],
        "@Alice0"
      )

      tx = %Transaction{
        address: "@Alice2",
        validation_stamp: %ValidationStamp{
          timestamp: ~U[2023-09-20 01:00:00Z],
          ledger_operations: %LedgerOperations{
            consumed_inputs: [
              %UnspentOutput{
                from: "@Bob3",
                amount: 200_000_000,
                type: :UCO,
                timestamp: ~U[2023-09-10 01:00:00Z]
              }
            ],
            transaction_movements: [
              %TransactionMovement{to: "@Charlie10", amount: 100_000_000, type: :UCO}
            ],
            unspent_outputs: [
              %UnspentOutput{
                from: "@Alice2",
                type: :UCO,
                amount: 100_000_000,
                timestamp: ~U[2023-09-20 01:00:00Z]
              }
            ]
          }
        }
      }

      GenesisInputLedger.update_chain_inputs(tx, "@Alice0", true)

      assert [
               %TransactionInput{
                 from: "@Tom5",
                 amount: 200_000_000,
                 type: :UCO,
                 timestamp: ~U[2023-09-10 05:00:00Z]
               },
               %TransactionInput{
                 from: "@Tom5",
                 amount: 100_000_000,
                 type: {:token, "token1", 0},
                 timestamp: ~U[2023-09-10 05:00:00Z]
               },
               %TransactionInput{
                 from: "@Alice2",
                 amount: 100_000_000,
                 type: :UCO,
                 timestamp: ~U[2023-09-20 01:00:00Z]
               }
             ] = GenesisInputLedger.get_unspent_inputs("@Alice0")
    end
  end
end
