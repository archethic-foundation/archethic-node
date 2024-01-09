defmodule Archethic.UTXOTest do
  use ArchethicCase

  alias Archethic.UTXO
  alias Archethic.UTXO.MemoryLedger

  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.UnspentOutput
  alias Archethic.TransactionChain.VersionedUnspentOutput
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  import Mox
  import Mock

  describe "load_transaction/2" do
    test "should load outputs as io storage nodes but not for chain" do
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
      |> stub(:get_genesis_address, fn
        ^destination_address -> destination_genesis_address
        addr -> addr
      end)

      me = self()

      MockUTXOLedger
      |> stub(:append, fn genesis_address, utxo ->
        send(me, {:append_utxo, genesis_address, utxo})
      end)

      with_mock(Election,
        chain_storage_nodes: fn
          ^destination_genesis_address, _ ->
            [%Node{first_public_key: Crypto.first_node_public_key()}]

          _, _ ->
            []
        end
      ) do
        UTXO.load_transaction(tx)

        assert [
                 %VersionedUnspentOutput{
                   unspent_output: %UnspentOutput{
                     from: ^transaction_address,
                     amount: 100_000_000,
                     type: :UCO
                   }
                 }
               ] = MemoryLedger.get_unspent_outputs(destination_genesis_address)

        assert [] = MemoryLedger.get_unspent_outputs(transaction_genesis_address)

        assert_receive {:append_utxo, ^destination_genesis_address,
                        %VersionedUnspentOutput{
                          unspent_output: %UnspentOutput{
                            from: ^transaction_address,
                            amount: 100_000_000,
                            type: :UCO
                          }
                        }}
      end
    end

    test "should load outputs as chain storage node" do
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
        ^transaction_address -> {:ok, transaction_genesis_address}
        _addr -> {:error, :not_found}
      end)

      me = self()

      MockUTXOLedger
      |> stub(:flush, fn genesis_address, utxos ->
        send(me, {:flush_outputs, genesis_address, utxos})
      end)

      with_mock(Election,
        chain_storage_nodes: fn
          ^transaction_genesis_address, _ ->
            [%Node{first_public_key: Crypto.first_node_public_key()}]

          _, _ ->
            []
        end
      ) do
        UTXO.load_transaction(tx)

        assert [
                 %VersionedUnspentOutput{
                   unspent_output: %UnspentOutput{
                     from: ^transaction_address,
                     type: :UCO,
                     timestamp: ~U[2023-09-10 05:00:00.000Z],
                     amount: 300_000_000
                   }
                 }
               ] = MemoryLedger.get_unspent_outputs(transaction_genesis_address)

        assert [] = MemoryLedger.get_unspent_outputs(destination_genesis_address)

        assert_receive {:flush_outputs, ^transaction_genesis_address,
                        [
                          %VersionedUnspentOutput{
                            unspent_output: %UnspentOutput{
                              from: ^transaction_address,
                              amount: 300_000_000
                            }
                          }
                        ]}
      end
    end

    test "should load genesis outputs as IO and then as chain storage node to consume outputs" do
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
              %TransactionMovement{to: destination_address, amount: 50_000_000, type: :UCO}
            ],
            unspent_outputs: [
              %UnspentOutput{
                from: transaction_address,
                amount: 50_000_000,
                type: :UCO,
                timestamp: ~U[2023-09-12 05:00:00.000Z]
              }
            ],
            consumed_inputs: [
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
      |> stub(:get_genesis_address, fn
        ^destination_address -> destination_genesis_address
        ^transaction_address -> transaction_genesis_address
        ^transaction_previous_address -> transaction_genesis_address
      end)
      |> stub(:find_genesis_address, fn
        ^transaction_address -> {:ok, transaction_genesis_address}
        _addr -> {:error, :not_found}
      end)

      me = self()

      MockUTXOLedger
      |> stub(:append, fn genesis_address, utxo ->
        send(me, {:add_utxo, genesis_address, utxo})
      end)
      |> stub(:flush, fn genesis_address, outputs ->
        send(me, {:flush_outputs, genesis_address, outputs})
      end)

      with_mock(Election,
        chain_storage_nodes: fn
          ^transaction_genesis_address, _ ->
            [%Node{first_public_key: Crypto.first_node_public_key()}]

          _, _ ->
            []
        end
      ) do
        UTXO.load_transaction(tx1)

        assert [
                 %VersionedUnspentOutput{
                   unspent_output: %UnspentOutput{
                     from: ^destination_address,
                     type: :UCO,
                     timestamp: ~U[2023-09-10 05:00:00.000Z],
                     amount: 100_000_000
                   }
                 }
               ] = MemoryLedger.get_unspent_outputs(transaction_genesis_address)

        UTXO.load_transaction(tx2)

        assert [
                 %VersionedUnspentOutput{
                   unspent_output: %UnspentOutput{
                     from: ^transaction_address,
                     amount: 50_000_000,
                     type: :UCO,
                     timestamp: ~U[2023-09-12 05:00:00.000Z]
                   }
                 }
               ] = MemoryLedger.get_unspent_outputs(transaction_genesis_address)
      end
    end
  end

  describe("get_unspent_outputs/1") do
    test "should return empty if there is nothing" do
      assert [] == UTXO.get_unspent_outputs(ArchethicCase.random_address())
    end

    test "should be able to return unspent outputs" do
      MemoryLedger.add_chain_utxo("@Alice0", %VersionedUnspentOutput{
        unspent_output: %UnspentOutput{
          from: "@Bob0",
          type: :UCO,
          amount: 100_000_000,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        },
        protocol_version: ArchethicCase.current_protocol_version()
      })

      assert [%VersionedUnspentOutput{unspent_output: %UnspentOutput{from: "@Bob0"}}] =
               UTXO.get_unspent_outputs("@Alice0")
    end

    test "should be able to return unspent outputs from disk if not in memory" do
      MockUTXOLedger
      |> stub(:stream, fn "@Alice0" ->
        [
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: "@Bob0",
              type: :UCO,
              amount: 100_000_000,
              timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
            },
            protocol_version: ArchethicCase.current_protocol_version()
          }
        ]
      end)

      assert [%VersionedUnspentOutput{unspent_output: %UnspentOutput{from: "@Bob0"}}] =
               UTXO.get_unspent_outputs("@Alice0")
    end
  end
end
