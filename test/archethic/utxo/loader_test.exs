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

      assert [^utxo] = "@Alice0" |> MemoryLedger.stream_unspent_outputs() |> Enum.to_list()
      assert_receive {:append, "@Alice0", ^utxo}
    end
  end

  describe "consume_inputs/2" do
    test "should consumed inputs and flush the new unspent outputs into memory and file ledger" do
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
        address: tx_address,
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
             ] =
               "@Alice0"
               |> MemoryLedger.stream_unspent_outputs()
               |> Enum.to_list()
    end

    test "should consumed inputs and flush after memory threshold" do
      {:ok, agent_pid} = Agent.start_link(fn -> [] end)

      MockUTXOLedger
      |> stub(:append, fn _genesis, utxo ->
        Agent.update(agent_pid, &([utxo | &1] |> Enum.reverse()))
      end)
      |> stub(:stream, fn _ -> Agent.get(agent_pid, & &1) end)

      utxos =
        Enum.map(1..5, fn _ ->
          %UnspentOutput{
            from: ArchethicCase.random_address(),
            type: :UCO,
            amount: 100_000_000,
            timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
          }
        end)

      Enum.each(utxos, fn utxo ->
        Loader.add_utxo(
          %VersionedUnspentOutput{
            unspent_output: utxo,
            protocol_version: ArchethicCase.current_protocol_version()
          },
          "@Alice0"
        )
      end)

      assert "@Alice0" |> MemoryLedger.stream_unspent_outputs() |> Enum.empty?()
      assert 5 = agent_pid |> Agent.get(& &1) |> length()

      me = self()

      MockUTXOLedger
      |> stub(:flush, fn genesis, utxos ->
        send(me, {:flush, genesis, utxos})
      end)

      tx_address = ArchethicCase.random_address()

      tx = %Transaction{
        address: tx_address,
        validation_stamp: %ValidationStamp{
          protocol_version: ArchethicCase.current_protocol_version(),
          timestamp: ~U[2023-09-10 05:00:00.000Z],
          ledger_operations: %LedgerOperations{
            transaction_movements: [],
            fee: 10_000_000,
            unspent_outputs: [
              %UnspentOutput{
                from: tx_address,
                amount: 490_000_000,
                type: :UCO,
                timestamp: ~U[2023-09-10 05:00:00.000Z]
              }
            ],
            consumed_inputs: Enum.take(utxos, 2)
          }
        },
        previous_public_key: ArchethicCase.random_public_key()
      }

      Loader.consume_inputs(tx, "@Alice0")

      assert_receive {:flush, "@Alice0",
                      [
                        %VersionedUnspentOutput{
                          unspent_output: %UnspentOutput{
                            amount: 100_000_000,
                            type: :UCO
                          }
                        },
                        %VersionedUnspentOutput{
                          unspent_output: %UnspentOutput{
                            amount: 100_000_000,
                            type: :UCO
                          }
                        },
                        %VersionedUnspentOutput{
                          unspent_output: %UnspentOutput{
                            amount: 100_000_000,
                            type: :UCO
                          }
                        },
                        %VersionedUnspentOutput{
                          unspent_output: %UnspentOutput{
                            from: ^tx_address,
                            amount: 490_000_000,
                            type: :UCO,
                            timestamp: ~U[2023-09-10 05:00:00.000Z]
                          }
                        }
                      ]}
    end

    test "should consumed inputs and flush after memory threshold and multiple input types" do
      {:ok, agent_pid} = Agent.start_link(fn -> [] end)

      MockUTXOLedger
      |> stub(:append, fn _genesis, utxo ->
        Agent.update(agent_pid, &([utxo | &1] |> Enum.reverse()))
      end)
      |> stub(:stream, fn _ -> Agent.get(agent_pid, & &1) end)

      utxos = [
        %UnspentOutput{
          from: ArchethicCase.random_address(),
          type: :UCO,
          amount: 100_000_000,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        },
        %UnspentOutput{
          from: ArchethicCase.random_address(),
          type: :UCO,
          amount: 100_000_000,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        },
        %UnspentOutput{
          from: ArchethicCase.random_address(),
          type: {:token, ArchethicCase.random_address(), 0},
          amount: 100_000_000,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        },
        %UnspentOutput{
          from: ArchethicCase.random_address(),
          type: {:token, ArchethicCase.random_address(), 0},
          amount: 300_000_000,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        }
      ]

      Enum.each(utxos, fn utxo ->
        Loader.add_utxo(
          %VersionedUnspentOutput{
            unspent_output: utxo,
            protocol_version: ArchethicCase.current_protocol_version()
          },
          "@Alice0"
        )
      end)

      assert "@Alice0" |> MemoryLedger.stream_unspent_outputs() |> Enum.empty?()
      assert 4 = agent_pid |> Agent.get(& &1) |> length()

      me = self()

      MockUTXOLedger
      |> stub(:flush, fn genesis, utxos ->
        send(me, {:flush, genesis, utxos})
      end)

      tx_address = ArchethicCase.random_address()

      tx = %Transaction{
        address: tx_address,
        validation_stamp: %ValidationStamp{
          protocol_version: ArchethicCase.current_protocol_version(),
          timestamp: ~U[2023-09-10 05:00:00.000Z],
          ledger_operations: %LedgerOperations{
            transaction_movements: [],
            fee: 10_000_000,
            unspent_outputs: [
              %UnspentOutput{
                from: tx_address,
                amount: 190_000_000,
                type: :UCO,
                timestamp: ~U[2023-09-10 05:00:00.000Z]
              }
            ],
            consumed_inputs: Enum.take(utxos, 2)
          }
        },
        previous_public_key: ArchethicCase.random_public_key()
      }

      Loader.consume_inputs(tx, "@Alice0")

      token_utxos =
        utxos
        |> Enum.reject(&(&1.type == :UCO))
        |> Enum.map(fn utxo ->
          %VersionedUnspentOutput{
            unspent_output: utxo,
            protocol_version: ArchethicCase.current_protocol_version()
          }
        end)

      expected_utxos =
        token_utxos ++
          [
            %VersionedUnspentOutput{
              unspent_output: %UnspentOutput{
                from: tx_address,
                amount: 190_000_000,
                type: :UCO,
                timestamp: ~U[2023-09-10 05:00:00.000Z]
              },
              protocol_version: ArchethicCase.current_protocol_version()
            }
          ]

      assert_receive {:flush, "@Alice0", ^expected_utxos}
    end
  end
end
