defmodule Archethic.Account.MemTables.TokenLedgerTest do
  @moduledoc false
  use ExUnit.Case

  @token1 <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

  alias Archethic.Account.MemTables.TokenLedger

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.VersionedTransactionInput

  import Mox

  test "add_unspent_output/3 insert a new entry in the tables" do
    {:ok, _pid} = TokenLedger.start_link()

    alice2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    bob3 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    charlie10 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

    :ok =
      TokenLedger.add_unspent_output(
        alice2,
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: bob3,
            amount: 300_000_000,
            type: {:token, @token1, 0},
            timestamp: ~U[2022-10-10 09:27:17Z]
          },
          protocol_version: 1
        }
      )

    :ok =
      TokenLedger.add_unspent_output(
        alice2,
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: charlie10,
            amount: 100_000_000,
            type: {:token, @token1, 1},
            timestamp: ~U[2022-10-10 09:27:17Z]
          },
          protocol_version: 1
        }
      )

    ledger_content = :ets.tab2list(:archethic_token_ledger)
    assert length(ledger_content) == 2

    assert Enum.any?(
             ledger_content,
             &(&1 ==
                 {{alice2, bob3, @token1, 0}, 300_000_000, false, ~U[2022-10-10 09:27:17Z], 1})
           )

    assert Enum.any?(
             ledger_content,
             &(&1 ==
                 {{alice2, charlie10, @token1, 1}, 100_000_000, false, ~U[2022-10-10 09:27:17Z],
                  1})
           )

    index_content = :ets.tab2list(:archethic_token_unspent_output_index)
    assert length(index_content) == 2
    assert Enum.any?(index_content, &(&1 == {alice2, bob3, @token1, 0}))
    assert Enum.any?(index_content, &(&1 == {alice2, charlie10, @token1, 1}))
  end

  describe "get_unspent_outputs/1" do
    test "should return an empty list when there are not entries" do
      {:ok, _pid} = TokenLedger.start_link()

      alice2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      assert [] = TokenLedger.get_unspent_outputs(alice2)
    end

    test "should return unspent transaction outputs" do
      {:ok, _pid} = TokenLedger.start_link()

      alice2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      bob3 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      charlie10 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      :ok =
        TokenLedger.add_unspent_output(
          alice2,
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: bob3,
              amount: 300_000_000,
              type: {:token, @token1, 0},
              timestamp: ~U[2022-10-10 09:27:17Z]
            },
            protocol_version: 1
          }
        )

      :ok =
        TokenLedger.add_unspent_output(
          alice2,
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: charlie10,
              amount: 100_000_000,
              type: {:token, @token1, 1},
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
                   type: {:token, @token1, 1},
                   timestamp: ~U[2022-10-10 09:27:17Z]
                 },
                 protocol_version: 1
               },
               %VersionedUnspentOutput{
                 unspent_output: %UnspentOutput{
                   from: ^bob3,
                   amount: 300_000_000,
                   type: {:token, @token1, 0},
                   timestamp: ~U[2022-10-10 09:27:17Z]
                 },
                 protocol_version: 1
               }
             ] = TokenLedger.get_unspent_outputs(alice2)
    end
  end

  test "spend_all_unspent_outputs/1 should mark all entries for an address as spent" do
    {:ok, _pid} = TokenLedger.start_link()

    alice2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    bob3 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    charlie10 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

    :ok =
      TokenLedger.add_unspent_output(alice2, %VersionedUnspentOutput{
        unspent_output: %UnspentOutput{
          from: bob3,
          amount: 300_000_000,
          type: {:token, @token1, 0},
          timestamp: ~U[2022-10-10 09:27:17Z]
        },
        protocol_version: 1
      })

    :ok =
      TokenLedger.add_unspent_output(alice2, %VersionedUnspentOutput{
        unspent_output: %UnspentOutput{
          from: charlie10,
          amount: 100_000_000,
          type: {:token, @token1, 1},
          timestamp: ~U[2022-10-10 09:27:17Z]
        },
        protocol_version: 1
      })

    MockDB
    |> expect(:start_inputs_writer, fn _, _ -> {:ok, self()} end)
    |> expect(:stop_inputs_writer, fn _ -> :ok end)
    |> stub(:append_input, fn _, _ -> :ok end)

    :ok = TokenLedger.spend_all_unspent_outputs(alice2)

    assert [] = TokenLedger.get_unspent_outputs(alice2)
  end

  describe "get_inputs/1" do
    test "convert unspent outputs" do
      {:ok, _pid} = TokenLedger.start_link()

      alice2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      bob3 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      charlie10 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      :ok =
        TokenLedger.add_unspent_output(
          alice2,
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: bob3,
              amount: 300_000_000,
              type: {:token, @token1, 0},
              timestamp: ~U[2022-10-10 09:27:17Z]
            },
            protocol_version: 1
          }
        )

      :ok =
        TokenLedger.add_unspent_output(
          alice2,
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: charlie10,
              amount: 100_000_000,
              type: {:token, @token1, 1},
              timestamp: ~U[2022-10-10 09:27:17Z]
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
      inputs = TokenLedger.get_inputs(alice2)
      assert length(inputs) == 2

      assert Enum.any?(
               inputs,
               &(&1 ==
                   %VersionedTransactionInput{
                     input: %TransactionInput{
                       from: bob3,
                       amount: 300_000_000,
                       type: {:token, @token1, 0},
                       spent?: false,
                       timestamp: ~U[2022-10-10 09:27:17Z]
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
                       type: {:token, @token1, 1},
                       spent?: false,
                       timestamp: ~U[2022-10-10 09:27:17Z]
                     },
                     protocol_version: 1
                   })
             )
    end

    test "should convert spent outputs" do
      {:ok, _pid} = TokenLedger.start_link()

      alice2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      bob3 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      charlie10 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      :ok =
        TokenLedger.add_unspent_output(
          alice2,
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: bob3,
              amount: 300_000_000,
              type: {:token, @token1, 0},
              timestamp: ~U[2022-10-10 09:27:17Z]
            },
            protocol_version: 1
          }
        )

      :ok =
        TokenLedger.add_unspent_output(
          alice2,
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: charlie10,
              amount: 100_000_000,
              type: {:token, @token1, 1},
              timestamp: ~U[2022-10-10 09:27:17Z]
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
              spent?: true,
              from: bob3,
              amount: 300_000_000,
              type: {:token, @token1, 0},
              timestamp: ~U[2022-10-10 09:27:17Z]
            },
            protocol_version: 1
          },
          %VersionedTransactionInput{
            input: %TransactionInput{
              spent?: true,
              from: charlie10,
              amount: 100_000_000,
              type: {:token, @token1, 1},
              timestamp: ~U[2022-10-10 09:27:17Z]
            },
            protocol_version: 1
          }
        ]
      end)

      :ok = TokenLedger.spend_all_unspent_outputs(alice2)

      # cannot rely on ordering because ETS are ordered by key and here the keys are randomly generated
      inputs = TokenLedger.get_inputs(alice2)
      assert length(inputs) == 2

      assert Enum.any?(
               inputs,
               &(&1 ==
                   %VersionedTransactionInput{
                     input: %TransactionInput{
                       from: bob3,
                       amount: 300_000_000,
                       type: {:token, @token1, 0},
                       spent?: true,
                       timestamp: ~U[2022-10-10 09:27:17Z]
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
                       type: {:token, @token1, 1},
                       spent?: true,
                       timestamp: ~U[2022-10-10 09:27:17Z]
                     },
                     protocol_version: 1
                   })
             )
    end
  end
end
