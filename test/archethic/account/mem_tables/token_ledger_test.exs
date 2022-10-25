defmodule Archethic.Account.MemTables.TokenLedgerTest do
  @moduledoc false
  use ExUnit.Case

  alias Archethic.Account.MemTables.TokenLedger

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.VersionedTransactionInput

  test "add_unspent_output/3 insert a new entry in the tables" do
    {:ok, _pid} = TokenLedger.start_link()

    :ok =
      TokenLedger.add_unspent_output(
        "@Alice2",
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: "@Bob3",
            amount: 300_000_000,
            type: {:token, "@Token1", 0},
            timestamp: ~U[2022-10-10 09:27:17.846Z]
          },
          protocol_version: 1
        }
      )

    :ok =
      TokenLedger.add_unspent_output(
        "@Alice2",
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: "@Charlie10",
            amount: 100_000_000,
            type: {:token, "@Token1", 1},
            timestamp: ~U[2022-10-10 09:27:17.846Z]
          },
          protocol_version: 1
        }
      )

    assert [
             {{"@Alice2", "@Bob3", "@Token1", 0}, 300_000_000, false,
              ~U[2022-10-10 09:27:17.846Z], 1},
             {{"@Alice2", "@Charlie10", "@Token1", 1}, 100_000_000, false,
              ~U[2022-10-10 09:27:17.846Z], 1}
           ] = :ets.tab2list(:archethic_token_ledger)

    assert [
             {"@Alice2", "@Bob3", "@Token1", 0},
             {"@Alice2", "@Charlie10", "@Token1", 1}
           ] = :ets.tab2list(:archethic_token_unspent_output_index)
  end

  describe "get_unspent_outputs/1" do
    test "should return an empty list when there are not entries" do
      {:ok, _pid} = TokenLedger.start_link()
      assert [] = TokenLedger.get_unspent_outputs("@Alice2")
    end

    test "should return unspent transaction outputs" do
      {:ok, _pid} = TokenLedger.start_link()

      :ok =
        TokenLedger.add_unspent_output(
          "@Alice2",
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: "@Bob3",
              amount: 300_000_000,
              type: {:token, "@Token1", 0},
              timestamp: ~U[2022-10-10 09:27:17.846Z]
            },
            protocol_version: 1
          }
        )

      :ok =
        TokenLedger.add_unspent_output(
          "@Alice2",
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: "@Charlie10",
              amount: 100_000_000,
              type: {:token, "@Token1", 1},
              timestamp: ~U[2022-10-10 09:27:17.846Z]
            },
            protocol_version: 1
          }
        )

      assert [
               %VersionedUnspentOutput{
                 unspent_output: %UnspentOutput{
                   from: "@Charlie10",
                   amount: 100_000_000,
                   type: {:token, "@Token1", 1},
                   timestamp: ~U[2022-10-10 09:27:17.846Z]
                 },
                 protocol_version: 1
               },
               %VersionedUnspentOutput{
                 unspent_output: %UnspentOutput{
                   from: "@Bob3",
                   amount: 300_000_000,
                   type: {:token, "@Token1", 0},
                   timestamp: ~U[2022-10-10 09:27:17.846Z]
                 },
                 protocol_version: 1
               }
             ] = TokenLedger.get_unspent_outputs("@Alice2")
    end
  end

  test "spend_all_unspent_outputs/1 should mark all entries for an address as spent" do
    {:ok, _pid} = TokenLedger.start_link()

    :ok =
      TokenLedger.add_unspent_output("@Alice2", %VersionedUnspentOutput{
        unspent_output: %UnspentOutput{
          from: "@Bob3",
          amount: 300_000_000,
          type: {:token, "@Token1", 0},
          timestamp: ~U[2022-10-10 09:27:17.846Z]
        },
        protocol_version: 1
      })

    :ok =
      TokenLedger.add_unspent_output("@Alice2", %VersionedUnspentOutput{
        unspent_output: %UnspentOutput{
          from: "@Charlie10",
          amount: 100_000_000,
          type: {:token, "@Token1", 1},
          timestamp: ~U[2022-10-10 09:27:17.846Z]
        },
        protocol_version: 1
      })

    :ok = TokenLedger.spend_all_unspent_outputs("@Alice2")

    assert [] = TokenLedger.get_unspent_outputs("@Alice2")
  end

  describe "get_inputs/1" do
    test "convert unspent outputs" do
      {:ok, _pid} = TokenLedger.start_link()

      :ok =
        TokenLedger.add_unspent_output(
          "@Alice2",
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: "@Bob3",
              amount: 300_000_000,
              type: {:token, "@Token1", 0},
              timestamp: ~U[2022-10-10 09:27:17.846Z]
            },
            protocol_version: 1
          }
        )

      :ok =
        TokenLedger.add_unspent_output(
          "@Alice2",
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: "@Charlie10",
              amount: 100_000_000,
              type: {:token, "@Token1", 1},
              timestamp: ~U[2022-10-10 09:27:17.846Z]
            },
            protocol_version: 1
          }
        )

      assert [
               %VersionedTransactionInput{
                 input: %TransactionInput{
                   from: "@Bob3",
                   amount: 300_000_000,
                   type: {:token, "@Token1", 0},
                   spent?: false,
                   timestamp: ~U[2022-10-10 09:27:17.846Z]
                 },
                 protocol_version: 1
               },
               %VersionedTransactionInput{
                 input: %TransactionInput{
                   from: "@Charlie10",
                   amount: 100_000_000,
                   type: {:token, "@Token1", 1},
                   spent?: false,
                   timestamp: ~U[2022-10-10 09:27:17.846Z]
                 },
                 protocol_version: 1
               }
             ] = TokenLedger.get_inputs("@Alice2")
    end

    test "should convert spent outputs" do
      {:ok, _pid} = TokenLedger.start_link()

      :ok =
        TokenLedger.add_unspent_output(
          "@Alice2",
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: "@Bob3",
              amount: 300_000_000,
              type: {:token, "@Token1", 0},
              timestamp: ~U[2022-10-10 09:27:17.846Z]
            },
            protocol_version: 1
          }
        )

      :ok =
        TokenLedger.add_unspent_output(
          "@Alice2",
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: "@Charlie10",
              amount: 100_000_000,
              type: {:token, "@Token1", 1},
              timestamp: ~U[2022-10-10 09:27:17.846Z]
            },
            protocol_version: 1
          }
        )

      :ok = TokenLedger.spend_all_unspent_outputs("@Alice2")

      assert [
               %VersionedTransactionInput{
                 input: %TransactionInput{
                   from: "@Bob3",
                   amount: 300_000_000,
                   type: {:token, "@Token1", 0},
                   spent?: true,
                   timestamp: ~U[2022-10-10 09:27:17.846Z]
                 },
                 protocol_version: 1
               },
               %VersionedTransactionInput{
                 input: %TransactionInput{
                   from: "@Charlie10",
                   amount: 100_000_000,
                   type: {:token, "@Token1", 1},
                   spent?: true,
                   timestamp: ~U[2022-10-10 09:27:17.846Z]
                 },
                 protocol_version: 1
               }
             ] = TokenLedger.get_inputs("@Alice2")
    end
  end
end
