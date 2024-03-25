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
  import ArchethicCase

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

  describe "add_chain_utxo/2" do
    setup do
      MockUTXOLedger
      |> stub(:list_genesis_addresses, fn -> [] end)

      MemoryLedger.start_link()

      :ok
    end

    test "should add new unspent output into the genesis's ledger" do
      MemoryLedger.add_chain_utxo("@Alice0", %VersionedUnspentOutput{
        unspent_output: %UnspentOutput{
          from: ArchethicCase.random_address(),
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond),
          type: :UCO,
          amount: 100_000_000
        }
      })

      assert [%VersionedUnspentOutput{unspent_output: %UnspentOutput{type: :UCO}}] =
               MemoryLedger.get_unspent_outputs("@Alice0")
    end

    test "should evict unspent outputs from memory if the size threshold is reached" do
      for i <- 1..5 do
        utxo = %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: ArchethicCase.random_address(),
            timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond),
            type: :UCO,
            amount: 100_000_000
          }
        }

        MemoryLedger.add_chain_utxo("@Alice0", utxo)

        expected_size = :erlang.external_size(utxo) * i

        if i < 4 do
          refute MemoryLedger.threshold_reached?("@Alice0")
          assert i == "@Alice0" |> MemoryLedger.get_unspent_outputs() |> Enum.count()
          assert %{size: ^expected_size} = MemoryLedger.get_genesis_stats("@Alice0")
        else
          assert MemoryLedger.threshold_reached?("@Alice0")
          assert [] = MemoryLedger.get_unspent_outputs("@Alice0")
          assert %{size: ^expected_size} = MemoryLedger.get_genesis_stats("@Alice0")
        end
      end
    end
  end

  describe "remove_consumed_input/2" do
    setup do
      MockUTXOLedger
      |> stub(:list_genesis_addresses, fn -> [] end)

      MemoryLedger.start_link()

      :ok
    end

    test "should remove the unspent outputs matching the consumed input" do
      utxo =
        %UnspentOutput{
          from: random_address(),
          type: :UCO,
          amount: 100_000_000,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        }
        |> VersionedUnspentOutput.wrap_unspent_output(current_protocol_version())

      address = random_address()

      MemoryLedger.add_chain_utxo(address, utxo)

      assert [^utxo] = MemoryLedger.get_unspent_outputs(address)

      MemoryLedger.remove_consumed_inputs(address, [utxo])

      assert MemoryLedger.get_unspent_outputs(address)
    end

    test "should reduce the size of unspent outputs in memory" do
      protocol_version = current_protocol_version()

      utxo1 =
        %UnspentOutput{
          from: random_address(),
          type: :UCO,
          amount: 100_000_000,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        }
        |> VersionedUnspentOutput.wrap_unspent_output(protocol_version)

      utxo2 =
        %UnspentOutput{
          from: random_address(),
          type: :UCO,
          amount: 200_000_000,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        }
        |> VersionedUnspentOutput.wrap_unspent_output(protocol_version)

      address = random_address()

      MemoryLedger.add_chain_utxo(address, utxo1)
      MemoryLedger.add_chain_utxo(address, utxo2)

      mem_utxos = MemoryLedger.get_unspent_outputs(address)

      assert length(mem_utxos) == 2
      assert Enum.all?([utxo1, utxo2], &Enum.member?(mem_utxos, &1))

      expected_size =
        address
        |> MemoryLedger.get_unspent_outputs()
        |> Enum.map(&:erlang.external_size/1)
        |> Enum.sum()

      assert %{size: ^expected_size} = MemoryLedger.get_genesis_stats(address)

      MemoryLedger.remove_consumed_inputs(address, [utxo2])

      expected_size = div(expected_size, 2)

      assert %{size: ^expected_size} = MemoryLedger.get_genesis_stats(address)
    end
  end
end
