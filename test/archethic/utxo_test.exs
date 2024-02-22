defmodule Archethic.UTXOTest do
  use ArchethicCase
  import ArchethicCase

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.Reward.MemTables.RewardTokens

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.UnspentOutput
  alias Archethic.TransactionChain.VersionedUnspentOutput
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer, as: TokenTransfer

  alias Archethic.UTXO
  alias Archethic.UTXO.MemoryLedger

  alias Archethic.TransactionFactory

  import Mox
  import Mock

  setup do
    start_supervised!(RewardTokens)

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.first_node_public_key(),
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-1)
    })

    :ok
  end

  describe "load_transaction/2" do
    test "should load outputs as io storage nodes but not for chain" do
      destination_previous_address = random_address()
      destination_genesis_address = random_address()

      transaction_address = random_address()
      transaction_previous_address = random_address()
      transaction_genesis_address = random_address()

      tx = %Transaction{
        address: transaction_address,
        type: :transfer,
        validation_stamp: %ValidationStamp{
          timestamp: ~U[2023-09-10 05:00:00.000Z],
          protocol_version: current_protocol_version(),
          ledger_operations: %LedgerOperations{
            transaction_movements: [
              %TransactionMovement{
                to: destination_genesis_address,
                amount: 100_000_000,
                type: :UCO
              }
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
        previous_public_key: random_public_key()
      }

      me = self()

      MockUTXOLedger
      |> stub(:append, fn genesis_address, utxo ->
        send(me, {:append_utxo, genesis_address, utxo})
      end)

      with_mock(Election, [:passthrough],
        chain_storage_node?: fn
          ^destination_genesis_address, _, _ -> true
          _, _, _ -> false
        end
      ) do
        UTXO.load_transaction(tx, transaction_genesis_address)

        assert [
                 %VersionedUnspentOutput{
                   unspent_output: %UnspentOutput{
                     from: ^transaction_address,
                     amount: 100_000_000,
                     type: :UCO
                   }
                 }
               ] =
                 destination_genesis_address
                 |> MemoryLedger.stream_unspent_outputs()
                 |> Enum.to_list()

        assert transaction_genesis_address
               |> MemoryLedger.stream_unspent_outputs()
               |> Enum.empty?()

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
      destination_previous_address = random_address()
      destination_genesis_address = random_address()

      transaction_address = random_address()
      transaction_previous_address = random_address()
      transaction_genesis_address = random_address()

      tx = %Transaction{
        address: transaction_address,
        type: :transfer,
        validation_stamp: %ValidationStamp{
          protocol_version: current_protocol_version(),
          timestamp: ~U[2023-09-10 05:00:00.000Z],
          ledger_operations: %LedgerOperations{
            transaction_movements: [
              %TransactionMovement{
                to: destination_genesis_address,
                amount: 100_000_000,
                type: :UCO
              }
            ],
            unspent_outputs: [
              %UnspentOutput{
                from: transaction_address,
                amount: 300_000_000,
                type: :UCO,
                timestamp: ~U[2023-09-10 05:00:00.000Z]
              }
            ],
            consumed_inputs:
              [
                %UnspentOutput{
                  from: transaction_previous_address,
                  amount: 200_000_000,
                  type: :UCO
                },
                %UnspentOutput{
                  from: destination_previous_address,
                  amount: 200_000_000,
                  type: :UCO
                }
              ]
              |> VersionedUnspentOutput.wrap_unspent_outputs(current_protocol_version())
          }
        },
        previous_public_key: random_public_key()
      }

      me = self()

      MockUTXOLedger
      |> stub(:flush, fn genesis_address, utxos ->
        send(me, {:flush_outputs, genesis_address, utxos})
      end)

      with_mock(Election, [:passthrough],
        chain_storage_node?: fn
          ^transaction_genesis_address, _, _ -> true
          _, _, _ -> false
        end
      ) do
        UTXO.load_transaction(tx, transaction_genesis_address)

        assert [
                 %VersionedUnspentOutput{
                   unspent_output: %UnspentOutput{
                     from: ^transaction_address,
                     type: :UCO,
                     timestamp: ~U[2023-09-10 05:00:00.000Z],
                     amount: 300_000_000
                   }
                 }
               ] =
                 transaction_genesis_address
                 |> MemoryLedger.stream_unspent_outputs()
                 |> Enum.to_list()

        assert destination_genesis_address
               |> MemoryLedger.stream_unspent_outputs()
               |> Enum.empty?()

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
      destination_address = random_address()
      destination_previous_address = random_address()
      destination_genesis_address = random_address()

      transaction_address = random_address()
      transaction_previous_address = random_address()
      transaction_genesis_address = random_address()

      tx1 = %Transaction{
        address: destination_address,
        type: :transfer,
        validation_stamp: %ValidationStamp{
          protocol_version: current_protocol_version(),
          timestamp: ~U[2023-09-10 05:00:00.000Z],
          ledger_operations: %LedgerOperations{
            transaction_movements: [
              %TransactionMovement{
                to: transaction_genesis_address,
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
            consumed_inputs:
              [
                %UnspentOutput{
                  from: destination_previous_address,
                  amount: 200_000_000,
                  type: :UCO
                },
                %UnspentOutput{
                  from: transaction_previous_address,
                  amount: 200_000_000,
                  type: :UCO
                }
              ]
              |> VersionedUnspentOutput.wrap_unspent_outputs(current_protocol_version())
          }
        },
        previous_public_key: random_public_key()
      }

      tx2 = %Transaction{
        address: transaction_address,
        type: :transfer,
        validation_stamp: %ValidationStamp{
          protocol_version: current_protocol_version(),
          timestamp: ~U[2023-09-12 05:00:00.000Z],
          ledger_operations: %LedgerOperations{
            transaction_movements: [
              %TransactionMovement{
                to: destination_genesis_address,
                amount: 50_000_000,
                type: :UCO
              }
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
              |> VersionedUnspentOutput.wrap_unspent_output(current_protocol_version())
            ]
          }
        },
        previous_public_key: random_public_key()
      }

      me = self()

      MockUTXOLedger
      |> stub(:append, fn genesis_address, utxo ->
        send(me, {:add_utxo, genesis_address, utxo})
      end)
      |> stub(:flush, fn genesis_address, outputs ->
        send(me, {:flush_outputs, genesis_address, outputs})
      end)

      with_mock(Election, [:passthrough],
        chain_storage_node?: fn
          ^transaction_genesis_address, _, _ -> true
          _, _, _ -> false
        end
      ) do
        UTXO.load_transaction(tx1, destination_genesis_address)

        assert [
                 %VersionedUnspentOutput{
                   unspent_output: %UnspentOutput{
                     from: ^destination_address,
                     type: :UCO,
                     timestamp: ~U[2023-09-10 05:00:00.000Z],
                     amount: 100_000_000
                   }
                 }
               ] =
                 transaction_genesis_address
                 |> MemoryLedger.stream_unspent_outputs()
                 |> Enum.to_list()

        UTXO.load_transaction(tx2, transaction_genesis_address)

        assert [
                 %VersionedUnspentOutput{
                   unspent_output: %UnspentOutput{
                     from: ^transaction_address,
                     amount: 50_000_000,
                     type: :UCO,
                     timestamp: ~U[2023-09-12 05:00:00.000Z]
                   }
                 }
               ] =
                 transaction_genesis_address
                 |> MemoryLedger.stream_unspent_outputs()
                 |> Enum.to_list()
      end
    end

    test "should load contract call unspent output" do
      destination_genesis_address = random_address()

      transaction_address = random_address()
      transaction_genesis_address = random_address()

      tx = %Transaction{
        address: transaction_address,
        type: :transfer,
        validation_stamp: %ValidationStamp{
          timestamp: ~U[2023-09-10 05:00:00.000Z],
          protocol_version: current_protocol_version(),
          recipients: [destination_genesis_address]
        },
        previous_public_key: random_public_key()
      }

      me = self()

      MockUTXOLedger
      |> stub(:append, fn genesis_address, utxo ->
        send(me, {:append_utxo, genesis_address, utxo})
      end)

      with_mock(Election, [:passthrough],
        chain_storage_node?: fn
          ^destination_genesis_address, _, _ -> true
          _, _, _ -> false
        end
      ) do
        UTXO.load_transaction(tx, transaction_genesis_address)

        assert [
                 %VersionedUnspentOutput{
                   unspent_output: %UnspentOutput{from: ^transaction_address, type: :call}
                 }
               ] =
                 destination_genesis_address
                 |> MemoryLedger.stream_unspent_outputs()
                 |> Enum.to_list()

        assert_receive {:append_utxo, ^destination_genesis_address,
                        %VersionedUnspentOutput{
                          unspent_output: %UnspentOutput{from: ^transaction_address, type: :call}
                        }}
      end
    end

    test "should not load utxos from past if they are already consumed, protocol_version >= 7" do
      transaction_address = random_address()
      transaction_genesis = random_address()

      destination1_genesis = random_address()
      destination2_genesis = random_address()
      destination3_genesis = random_address()

      token_address = random_address()
      token_type = {:token, token_address, 0}

      # Transaction to replicate, node is genesis node of all movements
      # destination1 chain has no transaction after this new one
      # destination2 has a chain after this new one and a transaction consume this input
      # destination3 has a chain after this new one and no transaction consume this input
      tx = %Transaction{
        address: transaction_address,
        type: :transfer,
        validation_stamp: %ValidationStamp{
          protocol_version: current_protocol_version(),
          timestamp: ~U[2023-09-12 05:00:00.000Z],
          ledger_operations: %LedgerOperations{
            transaction_movements: [
              %TransactionMovement{to: destination1_genesis, amount: 500_000, type: token_type},
              %TransactionMovement{to: destination2_genesis, amount: 300_000, type: token_type},
              %TransactionMovement{to: destination3_genesis, amount: 200_000, type: token_type}
            ],
            unspent_outputs: [],
            consumed_inputs: [
              %UnspentOutput{
                from: random_address(),
                amount: 1_000_000,
                type: token_type,
                timestamp: ~U[2023-09-10 05:00:00.000Z]
              }
            ]
          }
        },
        previous_public_key: random_public_key()
      }

      chain2_keep_address = random_address()
      chain2_consume_address = random_address()

      chain3_keep_address1 = random_address()
      chain3_keep_address2 = random_address()

      # Used for fees
      uco_utxo = %UnspentOutput{
        from: random_address(),
        amount: 100_000_000,
        type: :UCO,
        timestamp: ~U[2023-09-12 05:00:00.000Z]
      }

      chain1_utxo = %UnspentOutput{
        from: transaction_address,
        amount: 500_000,
        type: token_type,
        timestamp: ~U[2023-09-12 05:00:00.000Z]
      }

      chain2_utxo = %UnspentOutput{
        from: transaction_address,
        amount: 300_000,
        type: token_type,
        timestamp: ~U[2023-09-12 05:00:00.000Z]
      }

      chain3_utxo = %UnspentOutput{
        from: transaction_address,
        amount: 200_000,
        type: token_type,
        timestamp: ~U[2023-09-12 05:00:00.000Z]
      }

      chain2_keep_tx = TransactionFactory.create_valid_transaction([uco_utxo, chain2_utxo])

      chain2_consume_tx =
        TransactionFactory.create_valid_transaction([uco_utxo, chain2_utxo],
          ledger: %Ledger{
            token: %TokenLedger{
              transfers: [
                %TokenTransfer{
                  to: random_address(),
                  amount: 200_000,
                  token_address: token_address,
                  token_id: 0
                }
              ]
            }
          }
        )

      chain3_keep_tx1 = TransactionFactory.create_valid_transaction([uco_utxo, chain3_utxo])
      chain3_keep_tx2 = TransactionFactory.create_valid_transaction([uco_utxo, chain3_utxo])

      MockDB
      |> expect(:get_last_chain_address, 3, fn
        # Destination 1 does not have transaction after utxo timestamp so it will be stored
        ^destination1_genesis -> {random_address(), ~U[2023-09-11 05:00:00.000Z]}
        _ -> {random_address(), DateTime.utc_now()}
      end)
      |> expect(:list_chain_addresses, 2, fn
        # Destination 2 consume utxo in last transaction so it will not be stored
        ^destination2_genesis ->
          [
            {random_address(), ~U[2023-09-01 05:00:00.000Z]},
            {chain2_keep_address, ~U[2023-09-13 05:00:00.000Z]},
            {chain2_consume_address, ~U[2023-09-13 06:00:00.000Z]}
          ]

        # Destination 3 does not consume utxo so it will be stored
        ^destination3_genesis ->
          [
            {random_address(), ~U[2023-09-01 05:00:00.000Z]},
            {chain3_keep_address1, ~U[2023-09-13 05:00:00.000Z]},
            {chain3_keep_address2, ~U[2023-09-13 06:00:00.000Z]}
          ]
      end)
      |> expect(:get_transaction, 4, fn
        ^chain2_keep_address, _, _ -> {:ok, chain2_keep_tx}
        ^chain2_consume_address, _, _ -> {:ok, chain2_consume_tx}
        ^chain3_keep_address1, _, _ -> {:ok, chain3_keep_tx1}
        ^chain3_keep_address2, _, _ -> {:ok, chain3_keep_tx2}
      end)

      MockUTXOLedger |> stub(:append, fn _, _ -> :ok end)

      with_mock(Election, [:passthrough],
        chain_storage_node?: fn
          ^transaction_genesis, _, _ -> false
          _, _, _ -> true
        end
      ) do
        UTXO.load_transaction(tx, transaction_genesis)

        assert [%VersionedUnspentOutput{unspent_output: ^chain1_utxo}] =
                 destination1_genesis |> MemoryLedger.stream_unspent_outputs() |> Enum.to_list()

        assert [] =
                 destination2_genesis |> MemoryLedger.stream_unspent_outputs() |> Enum.to_list()

        assert [%VersionedUnspentOutput{unspent_output: ^chain3_utxo}] =
                 destination3_genesis |> MemoryLedger.stream_unspent_outputs() |> Enum.to_list()
      end
    end

    test "should not load utxos from past if they are already consumed, protocol_version < 7" do
      # Same test as before with transaction created using protocol_version 6

      transaction_address = random_address()
      transaction_genesis = random_address()

      destination1_address = random_address()
      destination1_genesis = random_address()

      destination2_address = random_address()
      destination2_genesis = random_address()

      destination3_address = random_address()
      destination3_genesis = random_address()

      token_address = random_address()
      token_type = {:token, token_address, 0}

      tx = %Transaction{
        address: transaction_address,
        type: :transfer,
        validation_stamp: %ValidationStamp{
          protocol_version: 6,
          timestamp: ~U[2023-09-12 05:00:00.000Z],
          ledger_operations: %LedgerOperations{
            transaction_movements: [
              %TransactionMovement{to: destination1_address, amount: 500_000, type: token_type},
              %TransactionMovement{to: destination2_address, amount: 300_000, type: token_type},
              %TransactionMovement{to: destination3_address, amount: 200_000, type: token_type}
            ],
            unspent_outputs: []
          }
        },
        previous_public_key: random_public_key()
      }

      chain2_keep_address = random_address()
      chain2_consume_address = random_address()

      chain3_keep_address1 = random_address()
      chain3_keep_address2 = random_address()

      chain1_utxo = %UnspentOutput{
        from: transaction_address,
        amount: 500_000,
        type: token_type,
        timestamp: ~U[2023-09-12 05:00:00.000Z]
      }

      chain2_utxo = %UnspentOutput{
        from: transaction_address,
        amount: 300_000,
        type: token_type,
        timestamp: ~U[2023-09-12 05:00:00.000Z]
      }

      chain3_utxo = %UnspentOutput{
        from: transaction_address,
        amount: 200_000,
        type: token_type,
        timestamp: ~U[2023-09-12 05:00:00.000Z]
      }

      uco_utxo = %UnspentOutput{
        from: random_address(),
        amount: 100_000_000,
        type: :UCO,
        timestamp: ~U[2023-09-12 05:00:00.000Z]
      }

      # type oracle used to have free fee and so no consumption of inputs
      chain2_keep_tx =
        TransactionFactory.create_valid_transaction([uco_utxo, chain2_utxo])
        |> set_ledger_operations_and_version([chain2_utxo])

      chain2_consume_tx =
        TransactionFactory.create_valid_transaction([uco_utxo, chain2_utxo],
          ledger: %Ledger{
            token: %TokenLedger{
              transfers: [
                %TokenTransfer{
                  to: random_address(),
                  amount: 300_000,
                  token_address: token_address,
                  token_id: 0
                }
              ]
            }
          }
        )
        |> set_ledger_operations_and_version([])

      chain3_keep_tx1 =
        TransactionFactory.create_valid_transaction([uco_utxo, chain3_utxo])
        |> set_ledger_operations_and_version([chain3_utxo])

      chain3_keep_tx2 =
        TransactionFactory.create_valid_transaction([uco_utxo, chain3_utxo])
        |> set_ledger_operations_and_version([chain3_utxo])

      MockDB
      |> expect(:get_genesis_address, 3, fn
        ^destination1_address -> destination1_genesis
        ^destination2_address -> destination2_genesis
        ^destination3_address -> destination3_genesis
      end)
      |> expect(:get_last_chain_address, 3, fn
        # Destination 1 does not have transaction after utxo timestamp so it will be ingested
        ^destination1_genesis -> {random_address(), ~U[2023-09-11 05:00:00.000Z]}
        _ -> {random_address(), DateTime.utc_now()}
      end)
      |> expect(:list_chain_addresses, 2, fn
        # Destination 2 consume utxo in last transaction so it will not be ingested
        ^destination2_genesis ->
          [
            {random_address(), ~U[2023-09-01 05:00:00.000Z]},
            {chain2_keep_address, ~U[2023-09-13 05:00:00.000Z]},
            {chain2_consume_address, ~U[2023-09-13 06:00:00.000Z]}
          ]

        # Destination 3 does not consume utxo so it will be ingested
        ^destination3_genesis ->
          [
            {random_address(), ~U[2023-09-01 05:00:00.000Z]},
            {chain3_keep_address1, ~U[2023-09-13 05:00:00.000Z]},
            {chain3_keep_address2, ~U[2023-09-13 06:00:00.000Z]}
          ]
      end)
      |> expect(:get_transaction, 4, fn
        ^chain2_keep_address, _, _ -> {:ok, chain2_keep_tx}
        ^chain2_consume_address, _, _ -> {:ok, chain2_consume_tx}
        ^chain3_keep_address1, _, _ -> {:ok, chain3_keep_tx1}
        ^chain3_keep_address2, _, _ -> {:ok, chain3_keep_tx2}
      end)

      MockUTXOLedger |> stub(:append, fn _, _ -> :ok end)

      with_mock(Election, [:passthrough],
        chain_storage_node?: fn
          ^transaction_genesis, _, _ -> false
          _, _, _ -> true
        end
      ) do
        UTXO.load_transaction(tx, transaction_genesis)

        assert [%VersionedUnspentOutput{unspent_output: ^chain1_utxo}] =
                 destination1_genesis |> MemoryLedger.stream_unspent_outputs() |> Enum.to_list()

        assert [] =
                 destination2_genesis |> MemoryLedger.stream_unspent_outputs() |> Enum.to_list()

        assert [%VersionedUnspentOutput{unspent_output: ^chain3_utxo}] =
                 destination3_genesis |> MemoryLedger.stream_unspent_outputs() |> Enum.to_list()
      end
    end
  end

  describe("stream_unspent_outputs/1") do
    test "should return empty if there is nothing" do
      assert random_address() |> UTXO.stream_unspent_outputs() |> Enum.empty?()
    end

    test "should be able to return unspent outputs" do
      MemoryLedger.add_chain_utxo("@Alice0", %VersionedUnspentOutput{
        unspent_output: %UnspentOutput{
          from: "@Bob0",
          type: :UCO,
          amount: 100_000_000,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        },
        protocol_version: current_protocol_version()
      })

      assert [%VersionedUnspentOutput{unspent_output: %UnspentOutput{from: "@Bob0"}}] =
               "@Alice0" |> UTXO.stream_unspent_outputs() |> Enum.to_list()
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
            protocol_version: current_protocol_version()
          }
        ]
      end)

      assert [%VersionedUnspentOutput{unspent_output: %UnspentOutput{from: "@Bob0"}}] =
               "@Alice0"
               |> UTXO.stream_unspent_outputs()
               |> Enum.to_list()
    end
  end

  defp set_ledger_operations_and_version(tx, unspent_outputs) do
    update_in(
      tx,
      [Access.key!(:validation_stamp), Access.key!(:ledger_operations)],
      fn ledger_operations ->
        %LedgerOperations{
          ledger_operations
          | consumed_inputs: [],
            unspent_outputs: unspent_outputs
        }
      end
    )
    |> put_in([Access.key!(:validation_stamp), Access.key!(:protocol_version)], 6)
  end
end
