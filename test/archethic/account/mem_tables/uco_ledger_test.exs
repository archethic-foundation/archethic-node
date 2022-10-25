defmodule Archethic.Account.MemTables.UCOLedgerTest do
  use ExUnit.Case, async: false

  alias Archethic.Account.MemTables.UCOLedger

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.VersionedTransactionInput

  test "add_unspent_output/3 should insert a new entry in the tables" do
    {:ok, _pid} = UCOLedger.start_link()

    :ok =
      UCOLedger.add_unspent_output(
        "@Alice2",
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: "@Bob3",
            amount: 300_000_000,
            type: :UCO,
            timestamp: ~U[2022-10-11 09:24:01.879Z]
          },
          protocol_version: 1
        }
      )

    :ok =
      UCOLedger.add_unspent_output(
        "@Alice2",
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: "@Charlie10",
            amount: 100_000_000,
            type: :UCO,
            timestamp: ~U[2022-10-11 09:24:01.879Z]
          },
          protocol_version: 1
        }
      )

    assert [
             {{"@Alice2", "@Bob3"}, 300_000_000, false, ~U[2022-10-11 09:24:01.879Z], false, 1},
             {{"@Alice2", "@Charlie10"}, 100_000_000, false, ~U[2022-10-11 09:24:01.879Z], false,
              1}
           ] = :ets.tab2list(:archethic_uco_ledger)

    assert [
             {"@Alice2", "@Bob3"},
             {"@Alice2", "@Charlie10"}
           ] = :ets.tab2list(:archethic_uco_unspent_output_index)
  end

  describe "get_unspent_outputs/1" do
    test "should return an empty list" do
      {:ok, _pid} = UCOLedger.start_link()
      assert [] = UCOLedger.get_unspent_outputs("@Alice2")
    end

    test "should return unspent transaction outputs" do
      {:ok, _pid} = UCOLedger.start_link()

      :ok =
        UCOLedger.add_unspent_output(
          "@Alice2",
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: "@Bob3",
              amount: 300_000_000,
              type: :UCO,
              timestamp: ~U[2022-10-11 09:24:01.879Z]
            },
            protocol_version: 1
          }
        )

      :ok =
        UCOLedger.add_unspent_output(
          "@Alice2",
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: "@Charlie10",
              amount: 100_000_000,
              type: :UCO,
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
                   type: :UCO,
                   timestamp: ~U[2022-10-10 09:27:17.846Z]
                 },
                 protocol_version: 1
               },
               %VersionedUnspentOutput{
                 unspent_output: %UnspentOutput{
                   from: "@Bob3",
                   amount: 300_000_000,
                   type: :UCO,
                   timestamp: ~U[2022-10-11 09:24:01.879Z]
                 },
                 protocol_version: 1
               }
             ] = UCOLedger.get_unspent_outputs("@Alice2")
    end
  end

  test "spend_all_unspent_outputs/1 should mark all entries for an address as spent" do
    {:ok, _pid} = UCOLedger.start_link()

    :ok =
      UCOLedger.add_unspent_output(
        "@Alice2",
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: "@Bob3",
            amount: 300_000_000,
            type: :UCO,
            timestamp: ~U[2022-10-11 09:24:01.879Z]
          },
          protocol_version: 1
        }
      )

    :ok =
      UCOLedger.add_unspent_output(
        "@Alice2",
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: "@Charlie10",
            amount: 100_000_000,
            type: :UCO,
            timestamp: ~U[2022-10-11 09:24:01.879Z]
          },
          protocol_version: 1
        }
      )

    :ok = UCOLedger.spend_all_unspent_outputs("@Alice2")
    assert [] = UCOLedger.get_unspent_outputs("@Alice2")
  end

  describe "get_inputs/1" do
    test "convert unspent outputs" do
      {:ok, _pid} = UCOLedger.start_link()

      :ok =
        UCOLedger.add_unspent_output(
          "@Alice2",
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: "@Bob3",
              amount: 300_000_000,
              type: :UCO,
              timestamp: ~U[2022-10-11 09:24:01.879Z]
            },
            protocol_version: 1
          }
        )

      :ok =
        UCOLedger.add_unspent_output(
          "@Alice2",
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: "@Charlie10",
              amount: 100_000_000,
              type: :UCO,
              timestamp: ~U[2022-10-11 09:24:01.879Z]
            },
            protocol_version: 1
          }
        )

      assert [
               %VersionedTransactionInput{
                 input: %TransactionInput{
                   from: "@Bob3",
                   amount: 300_000_000,
                   spent?: false,
                   type: :UCO,
                   timestamp: ~U[2022-10-11 09:24:01.879Z]
                 },
                 protocol_version: 1
               },
               %VersionedTransactionInput{
                 input: %TransactionInput{
                   from: "@Charlie10",
                   amount: 100_000_000,
                   spent?: false,
                   type: :UCO,
                   timestamp: ~U[2022-10-11 09:24:01.879Z]
                 },
                 protocol_version: 1
               }
             ] = UCOLedger.get_inputs("@Alice2")
    end

    test "should convert spent outputs" do
      {:ok, _pid} = UCOLedger.start_link()

      :ok =
        UCOLedger.add_unspent_output(
          "@Alice2",
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: "@Bob3",
              amount: 300_000_000,
              type: :UCO,
              timestamp: ~U[2022-10-11 09:24:01.879Z]
            },
            protocol_version: 1
          }
        )

      :ok =
        UCOLedger.add_unspent_output(
          "@Alice2",
          %VersionedUnspentOutput{
            unspent_output: %UnspentOutput{
              from: "@Charlie10",
              amount: 100_000_000,
              type: :UCO,
              timestamp: ~U[2022-10-11 09:24:01.879Z]
            },
            protocol_version: 1
          }
        )

      :ok = UCOLedger.spend_all_unspent_outputs("@Alice2")

      assert [
               %VersionedTransactionInput{
                 input: %TransactionInput{
                   from: "@Bob3",
                   amount: 300_000_000,
                   spent?: true,
                   type: :UCO,
                   timestamp: ~U[2022-10-11 09:24:01.879Z]
                 },
                 protocol_version: 1
               },
               %VersionedTransactionInput{
                 input: %TransactionInput{
                   from: "@Charlie10",
                   amount: 100_000_000,
                   spent?: true,
                   type: :UCO,
                   timestamp: ~U[2022-10-11 09:24:01.879Z]
                 },
                 protocol_version: 1
               }
             ] = UCOLedger.get_inputs("@Alice2")
    end
  end
end
