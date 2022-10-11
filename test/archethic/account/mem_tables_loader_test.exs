defmodule Archethic.Account.MemTablesLoaderTest do
  @moduledoc false
  use ArchethicCase

  alias Archethic.Account.MemTables.TokenLedger
  alias Archethic.Account.MemTables.UCOLedger
  alias Archethic.Account.MemTablesLoader

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  import Mox

  doctest Archethic.Account.MemTablesLoader

  alias Archethic.Reward.MemTables.RewardTokens, as: RewardMemTable
  alias Archethic.Reward.MemTablesLoader, as: RewardTableLoader

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    P2P.add_and_connect_node(%Node{
      first_public_key: "NodeKey",
      last_public_key: "NodeKey",
      reward_address: "@NodeKey",
      ip: {127, 0, 0, 1},
      port: 3000,
      geo_patch: "AAA"
    })

    MockDB
    |> stub(:list_transactions_by_type, fn :mint_rewards, [:address, :type] ->
      [
        %Transaction{
          address: "@RewardToken0",
          type: :mint_rewards,
          validation_stamp: %ValidationStamp{ledger_operations: %LedgerOperations{fee: 0}}
        },
        %Transaction{
          address: "@RewardToken1",
          type: :mint_rewards,
          validation_stamp: %ValidationStamp{ledger_operations: %LedgerOperations{fee: 0}}
        },
        %Transaction{
          address: "@RewardToken2",
          type: :mint_rewards,
          validation_stamp: %ValidationStamp{ledger_operations: %LedgerOperations{fee: 0}}
        },
        %Transaction{
          address: "@RewardToken3",
          type: :mint_rewards,
          validation_stamp: %ValidationStamp{ledger_operations: %LedgerOperations{fee: 0}}
        },
        %Transaction{
          address: "@RewardToken4",
          type: :mint_rewards,
          validation_stamp: %ValidationStamp{ledger_operations: %LedgerOperations{fee: 0}}
        }
      ]
    end)

    start_supervised!(RewardMemTable)
    start_supervised!(RewardTableLoader)

    :ok
  end

  describe "load_transaction/1" do
    test "should distribute unspent outputs" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-1000),
        available?: true,
        geo_patch: "AAA"
      })

      timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)
      assert :ok = MemTablesLoader.load_transaction(create_transaction(timestamp))

      [
        %UnspentOutput{
          from: "@Charlie3",
          amount: 1_900_000_000,
          type: :UCO,
          timestamp: ^timestamp
        },
        %UnspentOutput{from: "@Alice2", amount: 200_000_000, type: :UCO, timestamp: ^timestamp}
      ] = UCOLedger.get_unspent_outputs("@Charlie3")

      [%UnspentOutput{from: "@Charlie3", amount: 3_400_000_000, timestamp: ^timestamp}] =
        UCOLedger.get_unspent_outputs("@Tom4")

      [%UnspentOutput{from: "@Charlie3", amount: 100_000_000, timestamp: ^timestamp}] =
        UCOLedger.get_unspent_outputs(LedgerOperations.burning_address())

      assert [
               %UnspentOutput{
                 from: "@Charlie3",
                 amount: 1_000_000_000,
                 type: {:token, "@CharlieToken", 0},
                 timestamp: ^timestamp
               }
             ] = TokenLedger.get_unspent_outputs("@Bob3")
    end
  end

  describe "start_link/1" do
    setup do
      timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)

      MockDB
      |> stub(:list_transactions, fn _fields ->
        [create_transaction(timestamp)]
      end)

      %{timestamp: timestamp}
    end

    test "should query DB to load all the transactions", %{timestamp: timestamp} do
      assert {:ok, _} = MemTablesLoader.start_link()

      [
        %UnspentOutput{
          from: "@Charlie3",
          amount: 1_900_000_000,
          type: :UCO,
          timestamp: ^timestamp
        },
        %UnspentOutput{from: "@Alice2", amount: 200_000_000, type: :UCO, timestamp: ^timestamp}
      ] = UCOLedger.get_unspent_outputs("@Charlie3")

      [
        %UnspentOutput{
          from: "@Charlie3",
          amount: 3_400_000_000,
          type: :UCO,
          timestamp: ^timestamp
        }
      ] = UCOLedger.get_unspent_outputs("@Tom4")

      assert [
               %UnspentOutput{
                 from: "@Charlie3",
                 amount: 1_000_000_000,
                 type: {:token, "@CharlieToken", 0},
                 timestamp: ^timestamp
               }
             ] = TokenLedger.get_unspent_outputs("@Bob3")
    end
  end

  defp create_transaction(timestamp) do
    %Transaction{
      address: "@Charlie3",
      previous_public_key: "Charlie2",
      validation_stamp: %ValidationStamp{
        timestamp: timestamp,
        ledger_operations: %LedgerOperations{
          fee: 100_000_000,
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
              type: :UCO,
              timestamp: timestamp
            },
            %UnspentOutput{
              from: "@Charlie3",
              amount: 1_900_000_000,
              type: :UCO,
              timestamp: timestamp
            }
          ]
        }
      }
    }
  end

  describe "Reward Minting test" do
    test "Should display Reward Token as UCO in UnspentOutput of Recipient" do
      timestamp = DateTime.utc_now() |> DateTime.add(-186_400) |> DateTime.truncate(:millisecond)

      validation_time =
        DateTime.utc_now() |> DateTime.add(-86_400) |> DateTime.truncate(:millisecond)

      assert :ok =
               MemTablesLoader.load_transaction(
                 create_reward_transaction(timestamp, validation_time)
               )

      # uco ledger
      assert [
               %UnspentOutput{
                 from: "@Charlie3",
                 amount: 1_900_000_000,
                 type: :UCO,
                 timestamp: ^validation_time
               },
               %UnspentOutput{from: "@Alice2", amount: 200_000_000, type: :UCO}
             ] = UCOLedger.get_unspent_outputs("@Charlie3")

      assert [
               %UnspentOutput{
                 from: "@Charlie3",
                 amount: 3_600_000_000,
                 type: :UCO,
                 timestamp: ^validation_time
               }
             ] = UCOLedger.get_unspent_outputs("@Tom4")

      assert [
               %UnspentOutput{
                 from: "@Charlie3",
                 amount: 200_000_000,
                 type: :UCO,
                 timestamp: ^validation_time
               }
             ] = UCOLedger.get_unspent_outputs("@Bob3")

      #  token ledger
      assert [
               %UnspentOutput{
                 amount: 100_000_000,
                 from: "@Rob1",
                 reward?: false,
                 timestamp: ^timestamp,
                 type: {:token, "@WeatherNFT", 1}
               },
               %UnspentOutput{
                 from: "@RewardToken2",
                 amount: 5_000_000_000,
                 type: {:token, "@RewardToken2", 0},
                 timestamp: ^validation_time
               },
               %UnspentOutput{
                 from: "@RewardToken1",
                 amount: 5_000_000_000,
                 type: {:token, "@RewardToken1", 0},
                 timestamp: ^validation_time
               }
             ] = TokenLedger.get_unspent_outputs("@Charlie3")

      assert [] = TokenLedger.get_unspent_outputs("@Tom4")

      assert [
               %UnspentOutput{
                 from: "@Charlie3",
                 amount: 1_000_000_000,
                 type: {:token, "@CharlieToken", 0},
                 timestamp: ^validation_time
               }
             ] = TokenLedger.get_unspent_outputs("@Bob3")
    end
  end

  defp create_reward_transaction(timestamp, validation_time) do
    %Transaction{
      address: "@Charlie3",
      previous_public_key: "Charlie2",
      validation_stamp: %ValidationStamp{
        timestamp: validation_time,
        ledger_operations: %LedgerOperations{
          fee: 0,
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
              type: :UCO,
              timestamp: validation_time
            },
            %UnspentOutput{
              from: "@Charlie3",
              amount: 1_900_000_000,
              type: :UCO,
              timestamp: validation_time
            },
            %UnspentOutput{
              from: "@RewardToken1",
              amount: 5_000_000_000,
              type: {:token, "@RewardToken1", 0},
              reward?: true,
              timestamp: validation_time
            },
            %UnspentOutput{
              from: "@RewardToken2",
              amount: 5_000_000_000,
              type: {:token, "@RewardToken2", 0},
              reward?: true,
              timestamp: validation_time
            },
            %UnspentOutput{
              from: "@Rob1",
              amount: 100_000_000,
              type: {:token, "@WeatherNFT", 1},
              reward?: true,
              timestamp: timestamp
            }
          ]
        }
      }
    }
  end
end
