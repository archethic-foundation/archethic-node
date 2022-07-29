defmodule Archethic.Account.MemTablesLoaderTest do
  @moduledoc false
  use ArchethicCase

  alias Archethic.Account.MemTables.TokenLedger
  alias Archethic.Account.MemTables.UCOLedger
  alias Archethic.Account.MemTablesLoader

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  import Mox

  alias Archethic.Reward
  doctest Archethic.Account.MemTablesLoader

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    MockDB
    |> stub(:list_transactions_by_type, fn :mint_rewards, [:address, :type] ->
      [
        %Transaction{address: "@RewardToken0", type: :mint_rewards},
        %Transaction{address: "@RewardToken1", type: :mint_rewards},
        %Transaction{address: "@RewardToken2", type: :mint_rewards}
      ]
    end)

    start_supervised!(Reward.MemTables.RewardTokens)
    start_supervised!(Reward.MemTablesLoader)

    P2P.add_and_connect_node(%Node{
      first_public_key: "NodeKey",
      last_public_key: "NodeKey",
      reward_address: "@NodeKey",
      ip: {127, 0, 0, 1},
      port: 3000,
      geo_patch: "AAA"
    })

    :ok
  end

  describe "load_transaction/1" do
    test "should distribute unspent outputs" do
      assert :ok = MemTablesLoader.load_transaction(create_transaction())

      [
        %UnspentOutput{from: "@Charlie3", amount: 1_900_000_000, type: :UCO},
        %UnspentOutput{from: "@Alice2", amount: 200_000_000, type: :UCO}
      ] = UCOLedger.get_unspent_outputs("@Charlie3")

      [%UnspentOutput{from: "@Charlie3", amount: 3_400_000_000}] =
        UCOLedger.get_unspent_outputs("@Tom4")

      assert [
               %UnspentOutput{
                 from: "@Charlie3",
                 amount: 1_000_000_000,
                 type: {:token, "@CharlieToken", 0}
               }
             ] = TokenLedger.get_unspent_outputs("@Bob3")
    end
  end

  describe "start_link/1" do
    setup do
      MockDB
      |> stub(:list_transactions, fn _fields -> [create_transaction()] end)

      :ok
    end

    test "should query DB to load all the transactions" do
      assert {:ok, _} = MemTablesLoader.start_link()

      [
        %UnspentOutput{from: "@Charlie3", amount: 1_900_000_000, type: :UCO},
        %UnspentOutput{from: "@Alice2", amount: 200_000_000, type: :UCO}
      ] = UCOLedger.get_unspent_outputs("@Charlie3")

      [%UnspentOutput{from: "@Charlie3", amount: 3_400_000_000, type: :UCO}] =
        UCOLedger.get_unspent_outputs("@Tom4")

      assert [
               %UnspentOutput{
                 from: "@Charlie3",
                 amount: 1_000_000_000,
                 type: {:token, "@CharlieToken", 0}
               }
             ] = TokenLedger.get_unspent_outputs("@Bob3")
    end
  end

  defp create_transaction do
    %Transaction{
      address: "@Charlie3",
      previous_public_key: "Charlie2",
      validation_stamp: %ValidationStamp{
        timestamp: DateTime.utc_now(),
        ledger_operations: %LedgerOperations{
          transaction_movements: [
            %TransactionMovement{to: "@Tom4", amount: 3_400_000_000, type: :UCO},
            %TransactionMovement{
              to: "@Bob3",
              amount: 1_000_000_000,
              type: {:token, "@CharlieToken", 0}
            }
          ],
          unspent_outputs: [
            %UnspentOutput{
              from: "@Alice2",
              amount: 200_000_000,
              type: :UCO
            },
            %UnspentOutput{from: "@Charlie3", amount: 1_900_000_000, type: :UCO}
          ]
        }
      }
    }
  end

  describe "Reward Minting test" do
    test "Should display Reward Token as UCO in UnspentOutput of Recipient" do
      assert :ok = MemTablesLoader.load_transaction(create_reward_transaction())

      # uco ledger
      assert [
               %UnspentOutput{from: "@Charlie3", amount: 1_900_000_000, type: :UCO},
               %UnspentOutput{from: "@Alice2", amount: 200_000_000, type: :UCO}
             ] = UCOLedger.get_unspent_outputs("@Charlie3")

      assert [
               %UnspentOutput{from: "@Charlie3", amount: 3_600_000_000, type: :UCO}
             ] = UCOLedger.get_unspent_outputs("@Tom4")

      assert [
               %UnspentOutput{from: "@Charlie3", amount: 200_000_000, type: :UCO}
             ] = UCOLedger.get_unspent_outputs("@Bob3")

      #  token ledger
      assert [
               %UnspentOutput{
                 from: "@RewardToken2",
                 amount: 5_000_000_000,
                 type: {:token, "@RewardToken2", 0}
               },
               %UnspentOutput{
                 from: "@RewardToken1",
                 amount: 5_000_000_000,
                 type: {:token, "@RewardToken1", 0}
               }
             ] = TokenLedger.get_unspent_outputs("@Charlie3")

      assert [] = TokenLedger.get_unspent_outputs("@Tom4")

      assert [
               %UnspentOutput{
                 from: "@Charlie3",
                 amount: 1_000_000_000,
                 type: {:token, "@CharlieToken", 0}
               }
             ] = TokenLedger.get_unspent_outputs("@Bob3")
    end
  end

  defp create_reward_transaction() do
    %Transaction{
      address: "@Charlie3",
      previous_public_key: "Charlie2",
      validation_stamp: %ValidationStamp{
        timestamp: DateTime.utc_now(),
        ledger_operations: %LedgerOperations{
          transaction_movements: [
            %TransactionMovement{to: "@Tom4", amount: 3_400_000_000, type: :UCO},
            %TransactionMovement{
              to: "@Bob3",
              amount: 1_000_000_000,
              type: {:token, "@CharlieToken", 0}
            },
            %TransactionMovement{
              to: "@Tom4",
              amount: 200_000_000,
              type: {:token, "@RewardToken1", 0}
            },
            %TransactionMovement{
              to: "@Bob3",
              amount: 200_000_000,
              type: {:token, "@RewardToken2", 0}
            }
          ],
          unspent_outputs: [
            %UnspentOutput{
              from: "@Alice2",
              amount: 200_000_000,
              type: :UCO
            },
            %UnspentOutput{from: "@Charlie3", amount: 1_900_000_000, type: :UCO},
            %UnspentOutput{
              from: "@RewardToken1",
              amount: 5_000_000_000,
              type: {:token, "@RewardToken1", 0},
              reward?: true
            },
            %UnspentOutput{
              from: "@RewardToken2",
              amount: 5_000_000_000,
              type: {:token, "@RewardToken2", 0},
              reward?: true
            }
          ]
        }
      }
    }
  end
end
