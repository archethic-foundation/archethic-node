defmodule Archethic.Account.GenesisLoaderTest do
  use ArchethicCase

  alias Archethic.Account.{
    GenesisLoader,
    GenesisState,
    GenesisPendingLog,
    MemTables.GenesisInputLedger
  }

  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  import Mox
  import Mock

  describe "load_transaction/2" do
    setup do
      {:ok, _} = Archethic.Account.GenesisSupervisor.start_link()
      :ok
    end

    test "should load genesis inputs as io storage nodes but not for chain" do
      destination_address = ArchethicCase.random_address()
      destination_previous_address = ArchethicCase.random_address()
      destination_genesis_address = ArchethicCase.random_address()

      transaction_address = ArchethicCase.random_address()
      transaction_previous_address = ArchethicCase.random_address()
      transaction_genesis_address = ArchethicCase.random_address()

      tx = %Transaction{
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
                amount: 300_000_000,
                type: :UCO,
                timestamp: ~U[2023-09-10 05:00:00.000Z]
              }
            ],
            consumed_inputs: [
              %UnspentOutput{from: transaction_previous_address, amount: 200_000_000, type: :UCO},
              %UnspentOutput{from: destination_previous_address, amount: 200_000_000, type: :UCO}
            ]
          }
        },
        previous_public_key: ArchethicCase.random_public_key()
      }

      MockDB
      |> stub(:find_genesis_address, fn
        ^destination_address -> {:ok, destination_genesis_address}
        _ -> {:ok, transaction_genesis_address}
      end)

      with_mock(Election,
        chain_storage_nodes: fn
          ^destination_genesis_address, _ ->
            [%Node{first_public_key: Crypto.first_node_public_key()}]

          _, _ ->
            []
        end
      ) do
        GenesisLoader.load_transaction(tx, true)

        assert [
                 %VersionedTransactionInput{
                   input: %TransactionInput{
                     from: ^transaction_address,
                     amount: 100_000_000,
                     type: :UCO
                   }
                 }
               ] = GenesisInputLedger.get_unspent_inputs(destination_genesis_address)

        assert [] = GenesisInputLedger.get_unspent_inputs(transaction_genesis_address)

        assert GenesisInputLedger.get_unspent_inputs(destination_genesis_address) ==
                 GenesisPendingLog.stream(destination_genesis_address) |> Enum.to_list()
      end
    end

    test "should load genesis inputs as chain storage node" do
      destination_address = ArchethicCase.random_address()
      destination_previous_address = ArchethicCase.random_address()
      destination_genesis_address = ArchethicCase.random_address()

      transaction_address = ArchethicCase.random_address()
      transaction_previous_address = ArchethicCase.random_address()
      transaction_genesis_address = ArchethicCase.random_address()

      tx = %Transaction{
        address: transaction_address,
        validation_stamp: %ValidationStamp{
          protocol_version: ArchethicCase.current_protocol_version(),
          timestamp: ~U[2023-09-10 05:00:00.000Z],
          ledger_operations: %LedgerOperations{
            transaction_movements: [
              %TransactionMovement{to: destination_address, amount: 100_000_000, type: :UCO}
            ],
            unspent_outputs: [
              %UnspentOutput{
                from: transaction_address,
                amount: 300_000_000,
                type: :UCO,
                timestamp: ~U[2023-09-10 05:00:00.000Z]
              }
            ],
            consumed_inputs: [
              %UnspentOutput{from: transaction_previous_address, amount: 200_000_000, type: :UCO},
              %UnspentOutput{from: destination_previous_address, amount: 200_000_000, type: :UCO}
            ]
          }
        },
        previous_public_key: ArchethicCase.random_public_key()
      }

      MockDB
      |> stub(:find_genesis_address, fn
        ^destination_address -> {:ok, destination_genesis_address}
        _ -> {:ok, transaction_genesis_address}
      end)
      |> stub(:chain_size, fn
        ^transaction_genesis_address -> 1
        _ -> 0
      end)

      with_mock(Election,
        chain_storage_nodes: fn
          ^transaction_genesis_address, _ ->
            [%Node{first_public_key: Crypto.first_node_public_key()}]

          _, _ ->
            []
        end
      ) do
        GenesisLoader.load_transaction(tx, false)

        assert [
                 %VersionedTransactionInput{
                   input: %TransactionInput{
                     from: ^transaction_address,
                     type: :UCO,
                     timestamp: ~U[2023-09-10 05:00:00.000Z],
                     amount: 300_000_000
                   }
                 }
               ] = GenesisInputLedger.get_unspent_inputs(transaction_genesis_address)

        assert GenesisInputLedger.get_unspent_inputs(destination_genesis_address) |> Enum.empty?()
        assert GenesisPendingLog.stream(destination_genesis_address) |> Enum.empty?()

        assert GenesisPendingLog.stream(transaction_genesis_address) |> Enum.empty?()

        assert GenesisState.fetch(transaction_genesis_address) ==
                 GenesisInputLedger.get_unspent_inputs(transaction_genesis_address)
      end
    end

    test "should load genesis inputs as IO and then as chain storage node to consume inputs" do
      destination_address = ArchethicCase.random_address()
      destination_previous_address = ArchethicCase.random_address()
      destination_genesis_address = ArchethicCase.random_address()

      transaction_address = ArchethicCase.random_address()
      transaction_previous_address = ArchethicCase.random_address()
      transaction_genesis_address = ArchethicCase.random_address()

      tx1 = %Transaction{
        address: destination_address,
        validation_stamp: %ValidationStamp{
          protocol_version: ArchethicCase.current_protocol_version(),
          timestamp: ~U[2023-09-10 05:00:00.000Z],
          ledger_operations: %LedgerOperations{
            transaction_movements: [
              %TransactionMovement{
                to: transaction_previous_address,
                amount: 100_000_000,
                type: :UCO
              }
            ],
            unspent_outputs: [
              %UnspentOutput{
                from: destination_address,
                amount: 300_000_000,
                type: :UCO,
                timestamp: ~U[2023-09-10 05:00:00.000Z]
              }
            ],
            consumed_inputs: [
              %UnspentOutput{from: destination_previous_address, amount: 200_000_000, type: :UCO},
              %UnspentOutput{from: transaction_previous_address, amount: 200_000_000, type: :UCO}
            ]
          }
        },
        previous_public_key: ArchethicCase.random_public_key()
      }

      tx2 = %Transaction{
        address: transaction_address,
        validation_stamp: %ValidationStamp{
          protocol_version: ArchethicCase.current_protocol_version(),
          timestamp: ~U[2023-09-12 05:00:00.000Z],
          ledger_operations: %LedgerOperations{
            transaction_movements: [
              %TransactionMovement{to: destination_address, amount: 100_000_000, type: :UCO}
            ],
            unspent_outputs: [
              %UnspentOutput{
                from: transaction_address,
                amount: 300_000_000,
                type: :UCO,
                timestamp: ~U[2023-09-12 05:00:00.000Z]
              }
            ],
            consumed_inputs: [
              %UnspentOutput{
                from: transaction_previous_address,
                amount: 400_000_000,
                type: :UCO,
                timestamp: ~U[2023-09-08 05:00:00.000Z]
              },
              %UnspentOutput{
                from: destination_address,
                amount: 100_000_000,
                type: :UCO,
                timestamp: ~U[2023-09-10 05:00:00.000Z]
              }
            ]
          }
        },
        previous_public_key: ArchethicCase.random_public_key()
      }

      MockDB
      |> stub(:find_genesis_address, fn
        ^destination_address -> {:ok, destination_genesis_address}
        _ -> {:ok, transaction_genesis_address}
      end)
      |> stub(:chain_size, fn
        ^transaction_genesis_address -> 1
        ^destination_address -> 1
        _ -> 0
      end)

      with_mock(Election,
        chain_storage_nodes: fn
          ^transaction_genesis_address, _ ->
            [%Node{first_public_key: Crypto.first_node_public_key()}]

          _, _ ->
            []
        end
      ) do
        GenesisLoader.load_transaction(tx1, true)

        assert [
                 %VersionedTransactionInput{
                   input: %TransactionInput{
                     from: ^destination_address,
                     type: :UCO,
                     timestamp: ~U[2023-09-10 05:00:00.000Z],
                     amount: 100_000_000
                   }
                 }
               ] = GenesisInputLedger.get_unspent_inputs(transaction_genesis_address)

        assert transaction_genesis_address
               |> GenesisPendingLog.stream()
               |> Enum.to_list() ==
                 GenesisInputLedger.get_unspent_inputs(transaction_genesis_address)

        GenesisLoader.load_transaction(tx2, false)

        assert GenesisPendingLog.stream(transaction_genesis_address) |> Enum.empty?()

        assert [
                 %VersionedTransactionInput{
                   input: %TransactionInput{
                     from: ^transaction_address,
                     amount: 300_000_000,
                     type: :UCO,
                     timestamp: ~U[2023-09-12 05:00:00.000Z]
                   }
                 }
               ] = GenesisInputLedger.get_unspent_inputs(transaction_genesis_address)

        assert GenesisState.fetch(transaction_genesis_address) ==
                 GenesisInputLedger.get_unspent_inputs(transaction_genesis_address)
      end
    end
  end
end
