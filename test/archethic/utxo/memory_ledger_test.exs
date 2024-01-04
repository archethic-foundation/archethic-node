defmodule Archethic.UTXO.MemoryLedgerTest do
  use ExUnit.Case

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.UTXO.MemoryLedger

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  describe "start_link/1" do
    test "should fill the memory ledger from the files" do
      destination_address = ArchethicCase.random_address()
      destination_genesis_address = ArchethicCase.random_address()

      transaction_address = ArchethicCase.random_address()
      transaction_previous_address = ArchethicCase.random_address()
      transaction_genesis_address = ArchethicCase.random_address()

      %Transaction{
        address: transaction_address,
        validation_stamp: %ValidationStamp{
          timestamp: ~U[2023-09-10 05:00:00.000Z],
          protocol_version: ArchethicCase.current_protocol_version(),
          ledger_operations: %LedgerOperations{
            transaction_movements: [
              %TransactionMovement{to: destination_address, amount: 100_000_000, type: :UCO}
            ],
            unspent_outputs: [
              %UnspentOutput{
                from: transaction_address,
                amount: 100_000_000,
                type: :UCO,
                timestamp: ~U[2023-09-10 05:00:00.000Z]
              }
            ],
            consumed_inputs: [
              %UnspentOutput{from: transaction_previous_address, amount: 200_000_000, type: :UCO}
            ]
          }
        },
        previous_public_key: ArchethicCase.random_public_key()
      }

      MockUTXOLedger
      |> stub(:list_genesis_addresses, fn ->
        [destination_genesis_address, transaction_genesis_address]
      end)
      |> stub(:stream, fn
        ^destination_genesis_address ->
          [
            %VersionedUnspentOutput{
              unspent_output: %UnspentOutput{
                from: transaction_address,
                type: :UCO,
                timestamp: ~U[2023-09-10 05:00:00.000Z],
                amount: 100_000_000
              },
              protocol_version: ArchethicCase.current_protocol_version()
            }
          ]

        ^transaction_genesis_address ->
          [
            %VersionedUnspentOutput{
              unspent_output: %UnspentOutput{
                from: transaction_address,
                type: :UCO,
                timestamp: ~U[2023-09-10 05:00:00.000Z],
                amount: 100_000_000
              },
              protocol_version: ArchethicCase.current_protocol_version()
            }
          ]
      end)

      assert {:ok, _} = MemoryLedger.start_link()

      assert [
               %VersionedUnspentOutput{unspent_output: %UnspentOutput{from: ^transaction_address}}
             ] = MemoryLedger.get_unspent_outputs(destination_genesis_address)

      assert [
               %VersionedUnspentOutput{unspent_output: %UnspentOutput{from: ^transaction_address}}
             ] = MemoryLedger.get_unspent_outputs(transaction_genesis_address)
    end
  end
end
