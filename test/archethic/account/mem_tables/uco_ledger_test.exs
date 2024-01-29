defmodule Archethic.Account.MemTables.UCOLedgerTest do
  use ExUnit.Case, async: false

  alias Archethic.Account.MemTables.UCOLedger

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.VersionedTransactionInput

  import Mox

  test "add_unspent_output/3 should insert a new entry in the tables" do
    {:ok, _pid} = UCOLedger.start_link()

    alice2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    bob3 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    charlie10 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

    :ok =
      UCOLedger.add_unspent_output(
        alice2,
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: bob3,
            amount: 300_000_000,
            type: :UCO,
            timestamp: ~U[2022-10-11 09:24:01Z]
          },
          protocol_version: 1
        }
      )

    :ok =
      UCOLedger.add_unspent_output(
        alice2,
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: charlie10,
            amount: 100_000_000,
            type: :UCO,
            timestamp: ~U[2022-10-11 09:24:01Z]
          },
          protocol_version: 1
        }
      )

    # cannot rely on ordering because of randomness
    ledger_content = :ets.tab2list(:archethic_uco_ledger)
    assert length(ledger_content) == 2

    assert Enum.any?(
             ledger_content,
             &match?({{alice2, bob3}, 300_000_000, false, ~U[2022-10-11 09:24:01Z], _, 1}, &1)
           )

    assert Enum.any?(
             ledger_content,
             &match?(
               {{alice2, charlie10}, 100_000_000, false, ~U[2022-10-11 09:24:01Z], _, 1},
               &1
             )
           )

    index_content = :ets.tab2list(:archethic_uco_unspent_output_index)
    assert length(index_content) == 2
    assert Enum.any?(index_content, &(&1 == {alice2, bob3}))
    assert Enum.any?(index_content, &(&1 == {alice2, charlie10}))
  end

  describe "get_unspent_outputs/1" do
    test "should return an empty list" do
      {:ok, _pid} = UCOLedger.start_link()

      alice2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      assert [] = UCOLedger.get_unspent_outputs(alice2)
    end

    test "should return unspent transaction outputs" do
      {:ok, _pid} = UCOLedger.start_link()

      alice2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      bob3 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      charlie10 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      :ok =
        UCOLedger.add_unspent_output(
          alice2,
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: bob3,
              amount: 300_000_000,
              type: :UCO,
              timestamp: ~U[2022-10-11 09:24:01Z]
            },
            protocol_version: 1
          }
        )

      :ok =
        UCOLedger.add_unspent_output(
          alice2,
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: charlie10,
              amount: 100_000_000,
              type: :UCO,
              timestamp: ~U[2022-10-10 09:27:17Z]
            },
            protocol_version: 1
          }
        )

      assert [
               %VersionedUnspentOutput{
                 unspent_output: %UnspentOutput{
                   from: ^charlie10,
                   amount: 100_000_000,
                   type: :UCO,
                   timestamp: ~U[2022-10-10 09:27:17Z]
                 },
                 protocol_version: 1
               },
               %VersionedUnspentOutput{
                 unspent_output: %UnspentOutput{
                   from: ^bob3,
                   amount: 300_000_000,
                   type: :UCO,
                   timestamp: ~U[2022-10-11 09:24:01Z]
                 },
                 protocol_version: 1
               }
             ] = UCOLedger.get_unspent_outputs(alice2)
    end
  end

  test "spend_all_unspent_outputs/1 should mark all entries for an address as spent" do
    {:ok, _pid} = UCOLedger.start_link()

    alice2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    bob3 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    charlie10 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

    :ok =
      UCOLedger.add_unspent_output(
        alice2,
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: bob3,
            amount: 300_000_000,
            type: :UCO,
            timestamp: ~U[2022-10-11 09:24:01Z]
          },
          protocol_version: 1
        }
      )

    :ok =
      UCOLedger.add_unspent_output(
        alice2,
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: charlie10,
            amount: 100_000_000,
            type: :UCO,
            timestamp: ~U[2022-10-11 09:24:01Z]
          },
          protocol_version: 1
        }
      )

    MockDB
    |> expect(:start_inputs_writer, fn _, _ -> {:ok, self()} end)
    |> expect(:stop_inputs_writer, fn _ -> :ok end)
    |> stub(:append_input, fn _, _ -> :ok end)

    :ok = UCOLedger.spend_all_unspent_outputs(alice2)
    assert [] = UCOLedger.get_unspent_outputs(alice2)
  end

  describe "get_inputs/1" do
    test "convert unspent outputs" do
      {:ok, _pid} = UCOLedger.start_link()

      alice2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      bob3 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      charlie10 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      :ok =
        UCOLedger.add_unspent_output(
          alice2,
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: bob3,
              amount: 300_000_000,
              type: :UCO,
              timestamp: ~U[2022-10-11 09:24:01Z]
            },
            protocol_version: 1
          }
        )

      :ok =
        UCOLedger.add_unspent_output(
          alice2,
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: charlie10,
              amount: 100_000_000,
              type: :UCO,
              timestamp: ~U[2022-10-11 09:24:01Z]
            },
            protocol_version: 1
          }
        )

      MockDB
      |> expect(:start_inputs_writer, fn _, _ -> {:ok, self()} end)
      |> expect(:stop_inputs_writer, fn _ -> :ok end)
      |> stub(:append_input, fn _, _ -> :ok end)
      |> expect(:get_inputs, fn _, _ -> [] end)

      # cannot rely on ordering because ETS are ordered by key and here the keys are randomly generated
      inputs = UCOLedger.get_inputs(alice2)
      assert length(inputs) == 2

      assert Enum.any?(
               inputs,
               &(&1 ==
                   %VersionedTransactionInput{
                     input: %TransactionInput{
                       from: bob3,
                       amount: 300_000_000,
                       spent?: false,
                       type: :UCO,
                       timestamp: ~U[2022-10-11 09:24:01Z]
                     },
                     protocol_version: 1
                   })
             )

      assert Enum.any?(
               inputs,
               &(&1 ==
                   %VersionedTransactionInput{
                     input: %TransactionInput{
                       from: charlie10,
                       amount: 100_000_000,
                       spent?: false,
                       type: :UCO,
                       timestamp: ~U[2022-10-11 09:24:01Z]
                     },
                     protocol_version: 1
                   })
             )
    end

    test "should convert spent outputs" do
      {:ok, _pid} = UCOLedger.start_link()

      alice2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      bob3 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      charlie10 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      :ok =
        UCOLedger.add_unspent_output(
          alice2,
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: bob3,
              amount: 300_000_000,
              type: :UCO,
              timestamp: ~U[2022-10-11 09:24:01Z]
            },
            protocol_version: 1
          }
        )

      :ok =
        UCOLedger.add_unspent_output(
          alice2,
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: charlie10,
              amount: 100_000_000,
              type: :UCO,
              timestamp: ~U[2022-10-11 09:24:01Z]
            },
            protocol_version: 1
          }
        )

      MockDB
      |> expect(:start_inputs_writer, fn _, _ -> {:ok, self()} end)
      |> expect(:stop_inputs_writer, fn _ -> :ok end)
      |> stub(:append_input, fn _, _ -> :ok end)
      |> expect(:get_inputs, fn _, _ ->
        [
          %VersionedTransactionInput{
            input: %TransactionInput{
              from: bob3,
              amount: 300_000_000,
              spent?: true,
              type: :UCO,
              timestamp: ~U[2022-10-11 09:24:01Z]
            },
            protocol_version: 1
          },
          %VersionedTransactionInput{
            input: %TransactionInput{
              from: charlie10,
              amount: 100_000_000,
              spent?: true,
              type: :UCO,
              timestamp: ~U[2022-10-11 09:24:01Z]
            },
            protocol_version: 1
          }
        ]
      end)

      :ok = UCOLedger.spend_all_unspent_outputs(alice2)

      # cannot rely on ordering because ETS are ordered by key and here the keys are randomly generated
      inputs = UCOLedger.get_inputs(alice2)
      assert length(inputs) == 2

      assert Enum.any?(
               inputs,
               &(&1 ==
                   %VersionedTransactionInput{
                     input: %TransactionInput{
                       from: bob3,
                       amount: 300_000_000,
                       spent?: true,
                       type: :UCO,
                       timestamp: ~U[2022-10-11 09:24:01Z]
                     },
                     protocol_version: 1
                   })
             )

      assert Enum.any?(
               inputs,
               &(&1 ==
                   %VersionedTransactionInput{
                     input: %TransactionInput{
                       from: charlie10,
                       amount: 100_000_000,
                       spent?: true,
                       type: :UCO,
                       timestamp: ~U[2022-10-11 09:24:01Z]
                     },
                     protocol_version: 1
                   })
             )
    end
  end
end
