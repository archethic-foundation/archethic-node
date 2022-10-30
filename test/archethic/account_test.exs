defmodule Archethic.AccountTest do
  @moduledoc false
  use ExUnit.Case

  alias Archethic.Account
  alias Archethic.Account.MemTables.TokenLedger
  alias Archethic.Account.MemTables.UCOLedger

  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.Transaction

  alias Archethic.Reward.MemTables.RewardTokens
  alias Archethic.Reward.MemTablesLoader, as: RewardMemTableLoader

  import Mox

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

      start_supervised!(RewardTokens)
      start_supervised!(RewardMemTableLoader)
      start_supervised!(UCOLedger)
      start_supervised!(TokenLedger)
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
      timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)

      UCOLedger.add_unspent_output(
        "@Alice2",
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{from: "@Bob3", amount: 300_000_000, timestamp: timestamp},
          protocol_version: 1
        }
      )

      UCOLedger.add_unspent_output(
        "@Alice2",
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: "@Tom10",
            amount: 100_000_000,
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

      UCOLedger.spend_all_unspent_outputs("@Alice2")
      TokenLedger.spend_all_unspent_outputs("@Alice2")

      assert %{uco: 0, token: %{}} == Account.get_balance("@Alice2")
    end
  end
end
