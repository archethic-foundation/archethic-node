defmodule Archethic.AccountTest do
  @moduledoc false

  alias Archethic.Account
  alias Archethic.Account.MemTables.TokenLedger
  alias Archethic.Account.MemTables.UCOLedger
  alias Archethic.Account.MemTablesLoader

  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.VersionedTransactionInput

  alias Archethic.TransactionFactory

  import Mox
  import ArchethicCase

  use ArchethicCase

  setup :set_mox_global

  describe "get_balance/1" do
    setup do
      stub(MockDB, :list_transactions_by_type, fn _, _ ->
        [
          %Transaction{
            address: "@RewardToken0",
            type: :mint_rewards,
            validation_stamp: %ValidationStamp{
              protocol_version: 1,
              ledger_operations: %LedgerOperations{fee: 0}
            }
          },
          %Transaction{
            address: "@RewardToken1",
            type: :mint_rewards,
            validation_stamp: %ValidationStamp{
              protocol_version: 1,
              ledger_operations: %LedgerOperations{fee: 0}
            }
          },
          %Transaction{
            address: "@RewardToken2",
            type: :mint_rewards,
            validation_stamp: %ValidationStamp{
              protocol_version: 1,
              ledger_operations: %LedgerOperations{fee: 0}
            }
          },
          %Transaction{
            address: "@RewardToken3",
            type: :mint_rewards,
            validation_stamp: %ValidationStamp{
              protocol_version: 1,
              ledger_operations: %LedgerOperations{fee: 0}
            }
          },
          %Transaction{
            address: "@RewardToken4",
            type: :mint_rewards,
            validation_stamp: %ValidationStamp{
              protocol_version: 1,
              ledger_operations: %LedgerOperations{fee: 0}
            }
          }
        ]
      end)

      :ok
    end

    test "should return the sum of unspent outputs amounts" do
      timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)

      UCOLedger.add_unspent_output(
        "@Alice2",
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: "@Bob3",
            amount: 300_000_000,
            type: :UCO,
            timestamp: timestamp
          },
          protocol_version: 1
        }
      )

      UCOLedger.add_unspent_output(
        "@Alice2",
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: "@Tom10",
            amount: 100_000_000,
            type: :UCO,
            timestamp: timestamp
          },
          protocol_version: 1
        }
      )

      TokenLedger.add_unspent_output(
        "@Alice2",
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: "@Charlie2",
            amount: 10_000_000_000,
            type: {:token, "@CharlieToken", 0},
            timestamp: timestamp
          },
          protocol_version: 1
        }
      )

      assert %{uco: 400_000_000, token: %{{"@CharlieToken", 0} => 10_000_000_000}} ==
               Account.get_balance("@Alice2")
    end

    test "should return 0 when no unspent outputs associated" do
      assert %{uco: 0, token: %{}} == Account.get_balance("@Alice2")
    end

    test "should return 0 when all the unspent outputs have been spent" do
      timestamp = DateTime.utc_now() |> DateTime.truncate(:second)

      alice2_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      bob3_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      charlie2_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      tom10_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      charlie_token_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      UCOLedger.add_unspent_output(
        alice2_address,
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: bob3_address,
            amount: 300_000_000,
            timestamp: timestamp
          },
          protocol_version: 1
        }
      )

      UCOLedger.add_unspent_output(
        alice2_address,
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: tom10_address,
            amount: 100_000_000,
            timestamp: timestamp
          },
          protocol_version: 1
        }
      )

      TokenLedger.add_unspent_output(
        alice2_address,
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: charlie2_address,
            amount: 10_000_000_000,
            type: {:token, charlie_token_address, 0},
            timestamp: timestamp
          },
          protocol_version: 1
        }
      )

      MockDB
      |> stub(:start_inputs_writer, fn _, _ -> {:ok, self()} end)
      |> stub(:stop_inputs_writer, fn _ -> :ok end)
      |> stub(:append_input, fn _, _ -> :ok end)

      UCOLedger.spend_all_unspent_outputs(alice2_address)
      TokenLedger.spend_all_unspent_outputs(alice2_address)

      assert %{uco: 0, token: %{}} == Account.get_balance(alice2_address)
    end
  end

  test "should return both UCO and TOKEN spent" do
    timestamp = DateTime.utc_now() |> DateTime.truncate(:second)

    alice2_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    bob3_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    charlie2_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    tom10_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    charlie_token_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

    UCOLedger.add_unspent_output(
      alice2_address,
      %VersionedUnspentOutput{
        unspent_output: %UnspentOutput{
          from: bob3_address,
          amount: 300_000_000,
          timestamp: timestamp
        },
        protocol_version: 1
      }
    )

    UCOLedger.add_unspent_output(
      alice2_address,
      %VersionedUnspentOutput{
        unspent_output: %UnspentOutput{
          from: tom10_address,
          amount: 100_000_000,
          timestamp: timestamp
        },
        protocol_version: 1
      }
    )

    TokenLedger.add_unspent_output(
      alice2_address,
      %VersionedUnspentOutput{
        unspent_output: %UnspentOutput{
          from: charlie2_address,
          amount: 10_000_000_000,
          type: {:token, charlie_token_address, 0},
          timestamp: timestamp
        },
        protocol_version: 1
      }
    )

    MockDB
    |> stub(:start_inputs_writer, fn _, _ -> {:ok, self()} end)
    |> stub(:stop_inputs_writer, fn _ -> :ok end)
    |> stub(:append_input, fn _, _ -> :ok end)
    |> stub(:get_inputs, fn
      :UCO, _ ->
        [
          %VersionedTransactionInput{
            input: %TransactionInput{
              from: tom10_address,
              amount: 100_000_000,
              type: :UCO,
              timestamp: timestamp,
              spent?: true
            },
            protocol_version: 1
          },
          %VersionedTransactionInput{
            input: %TransactionInput{
              from: bob3_address,
              amount: 300_000_000,
              type: :UCO,
              timestamp: timestamp,
              spent?: true
            },
            protocol_version: 1
          }
        ]

      :token, _ ->
        [
          %VersionedTransactionInput{
            input: %TransactionInput{
              from: charlie2_address,
              amount: 10_000_000_000,
              type: {:token, charlie_token_address, 0},
              timestamp: timestamp,
              spent?: true
            },
            protocol_version: 1
          }
        ]
    end)

    UCOLedger.spend_all_unspent_outputs(alice2_address)
    TokenLedger.spend_all_unspent_outputs(alice2_address)

    inputs = Account.get_inputs(alice2_address)

    assert 3 == length(inputs)

    assert Enum.any?(
             inputs,
             &(&1 == %VersionedTransactionInput{
                 input: %TransactionInput{
                   from: charlie2_address,
                   amount: 10_000_000_000,
                   type: {:token, charlie_token_address, 0},
                   timestamp: timestamp,
                   spent?: true
                 },
                 protocol_version: 1
               })
           )

    assert Enum.any?(
             inputs,
             &(&1 == %VersionedTransactionInput{
                 input: %TransactionInput{
                   from: tom10_address,
                   amount: 100_000_000,
                   type: :UCO,
                   timestamp: timestamp,
                   spent?: true
                 },
                 protocol_version: 1
               })
           )

    assert Enum.any?(
             inputs,
             &(&1 == %VersionedTransactionInput{
                 input: %TransactionInput{
                   from: bob3_address,
                   amount: 300_000_000,
                   type: :UCO,
                   timestamp: timestamp,
                   spent?: true
                 },
                 protocol_version: 1
               })
           )
  end

  describe("get_unspent_outputs/1") do
    test "should return empty if there is nothing" do
      assert [] == Account.get_unspent_outputs(random_address())
    end

    test "should be able to store and return state utxo" do
      MockDB
      |> stub(:list_io_transactions, fn _ -> [] end)
      |> stub(:list_transactions, fn _ -> [] end)
      
      MemTablesLoader.start_link()

      encoded_state = :crypto.strong_rand_bytes(10)

      state_utxo = %UnspentOutput{
        type: :state,
        encoded_payload: encoded_state
      }

      # some ucos are necessary for TransactionFactory.create_valid_transaction
      uco_utxo = %UnspentOutput{
        amount: 200_000_000,
        from: ArchethicCase.random_address(),
        type: :UCO,
        timestamp: DateTime.utc_now()
      }
      

      tx = TransactionFactory.create_valid_transaction([uco_utxo], state: encoded_state)
      Account.load_transaction(tx, io_transaction?: false)

      assert utxos = Account.get_unspent_outputs(tx.address)
      assert length(utxos) == 2
      assert Enum.any?(utxos, &match?(%VersionedUnspentOutput{unspent_output: ^state_utxo}, &1))
    end
  end
end
