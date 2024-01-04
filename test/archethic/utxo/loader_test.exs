defmodule Archethic.UTXO.LoaderTest do
  use ArchethicCase

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.UTXO.Loader
  alias Archethic.UTXO.MemoryLedger

  setup do
    PartitionSupervisor.start_link(
      child_spec: Loader,
      name: Archethic.UTXO.LoaderSupervisor,
      partitions: 1
    )

    :ok
  end

  import Mox

  describe "add_utxo/2" do
    test "should write the unspent output into memory and file ledger" do
      utxo = %VersionedUnspentOutput{
        unspent_output: %UnspentOutput{
          from: ArchethicCase.random_address(),
          type: :UCO,
          amount: 100_000_000,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        },
        protocol_version: ArchethicCase.current_protocol_version()
      }

      me = self()

      MockUTXOLedger
      |> stub(:append, fn genesis, utxo ->
        send(me, {:append, genesis, utxo})
      end)

      Loader.add_utxo(utxo, "@Alice0")

      assert [^utxo] = MemoryLedger.get_unspent_outputs("@Alice0")
      assert_receive {:append, "@Alice0", ^utxo}
    end
  end

  describe "consume_inputs/2" do
    test "should consumed inputs and flusth the new unspent outputs into memory and file ledger" do
      utxo = %VersionedUnspentOutput{
        unspent_output: %UnspentOutput{
          from: ArchethicCase.random_address(),
          type: :UCO,
          amount: 100_000_000,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        },
        protocol_version: ArchethicCase.current_protocol_version()
      }

      me = self()

      MockUTXOLedger
      |> stub(:append, fn genesis, utxo ->
        send(me, {:append, genesis, utxo})
      end)

      Loader.add_utxo(utxo, "@Alice0")

      tx_address = ArchethicCase.random_address()

      tx = %Transaction{
        address: ArchethicCase.random_address(),
        validation_stamp: %ValidationStamp{
          protocol_version: ArchethicCase.current_protocol_version(),
          timestamp: ~U[2023-09-10 05:00:00.000Z],
          ledger_operations: %LedgerOperations{
            transaction_movements: [],
            fee: 10_000_000,
            unspent_outputs: [
              %UnspentOutput{
                from: tx_address,
                amount: 90_000_000,
                type: :UCO,
                timestamp: ~U[2023-09-10 05:00:00.000Z]
              }
            ],
            consumed_inputs: [
              utxo.unspent_output
            ]
          }
        },
        previous_public_key: ArchethicCase.random_public_key()
      }

      MockUTXOLedger
      |> stub(:flush, fn genesis, utxos ->
        send(me, {:flush, genesis, utxos})
      end)

      Loader.consume_inputs(tx, "@Alice0")

      assert_receive {:flush, "@Alice0",
                      [
                        %VersionedUnspentOutput{
                          unspent_output: %UnspentOutput{
                            from: ^tx_address,
                            amount: 90_000_000
                          }
                        }
                      ]}

      assert [
               %VersionedUnspentOutput{
                 unspent_output: %UnspentOutput{from: ^tx_address, amount: 90_000_000}
               }
             ] = MemoryLedger.get_unspent_outputs("@Alice0")
    end
  end
end
