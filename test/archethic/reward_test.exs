defmodule Archethic.RewardTest do
  use ArchethicCase
  use ExUnitProperties

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.Reward
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer

  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction

  alias Archethic.Reward.MemTables.RewardTokens
  alias Archethic.Reward.MemTablesLoader, as: RewardMemTableLoader

  alias Archethic.Account
  alias Archethic.Account.MemTables.TokenLedger
  alias Archethic.Account.MemTables.UCOLedger
  alias Archethic.Account.MemTablesLoader, as: AccountTablesLoader

  alias Archethic.SharedSecrets.MemTables.NetworkLookup

  import Mox

  doctest Reward

  setup do
    P2P.add_and_connect_node(%Node{
      first_public_key: "KEY1",
      last_public_key: "KEY1",
      geo_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now(),
      average_availability: 1.0,
      reward_address: "ADR1"
    })

    P2P.add_and_connect_node(%Node{
      first_public_key: "KEY2",
      last_public_key: "KEY2",
      geo_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now(),
      average_availability: 1.0,
      reward_address: "ADR2"
    })
  end

  test "get_transfers should create transfer transaction" do
    MockUCOPriceProvider
    |> stub(:fetch, fn _pairs ->
      {:ok, %{"eur" => 0.10, "usd" => 0.10}}
    end)

    address = :crypto.strong_rand_bytes(32)
    token_address1 = :crypto.strong_rand_bytes(32)
    token_address2 = :crypto.strong_rand_bytes(32)

    NetworkLookup.set_network_pool_address(address)

    reward_amount = Reward.validation_nodes_reward()

    reward_amount2 = reward_amount - 10

    unspent_outputs1 = %UnspentOutput{
      from: :crypto.strong_rand_bytes(32),
      amount: reward_amount * 2,
      type: {:token, token_address1, 0}
    }

    unspent_outputs2 = %UnspentOutput{
      from: :crypto.strong_rand_bytes(32),
      amount: reward_amount2,
      type: {:token, token_address2, 0}
    }

    TokenLedger.add_unspent_output(address, unspent_outputs1, DateTime.utc_now())
    TokenLedger.add_unspent_output(address, unspent_outputs2, DateTime.utc_now())

    assert [
             %Transfer{
               amount: 10,
               to: "ADR1",
               token: ^token_address1
             },
             %Transfer{
               amount: ^reward_amount2,
               to: "ADR1",
               token: ^token_address2
             },
             %Transfer{
               amount: ^reward_amount,
               to: "ADR2",
               token: ^token_address1
             }
           ] = Reward.get_transfers()
  end

  describe "Reward Ops:" do
    setup do
      #  start supervised  ...
      MockDB
      |> stub(:list_transactions_by_type, fn :mint_rewards, [:address, :type] ->
        [
          %Transaction{address: "@RewardToken0", type: :mint_rewards},
          %Transaction{address: "@RewardToken1", type: :mint_rewards},
          %Transaction{address: "@RewardToken2", type: :mint_rewards},
          %Transaction{address: "@RewardToken3", type: :mint_rewards},
          %Transaction{address: "@RewardToken4", type: :mint_rewards}
        ]
      end)

      start_supervised({RewardTokens, []})
      start_supervised({RewardMemTableLoader, []})
      start_supervised(UCOLedger)
      start_supervised(TokenLedger)
      :ok
    end

    test "Balance Should be updated with UCO ,for reward movements " do
      Enum.each(get_reward_transactions(), &AccountTablesLoader.load_transaction(&1))

      # @Ada1
      # from alen2: 2uco, dan2: 19uco, rewardtoken1: 50, rewardtoken2: 50
      assert %{
               uco: 2_100_000_000,
               token: %{
                 {"@RewardToken1", 0} => 5_000_000_000,
                 {"@RewardToken2", 0} => 5_000_000_000
               }
             } == Account.get_balance("@Ada1")

      # to tom7 34 uco and 2 rewardtoken1
      assert %{uco: 3_600_000_000, token: %{}} == Account.get_balance("@Tom7")

      # to bob5 10 aeusd, from tom9 1aeusd token,2rewardtoken2
      assert %{uco: 200_000_000, token: %{{"@AEUSDTOKEN", 0} => 1_100_000_000}} ==
               Account.get_balance("@Bob5")

      # 2 rewardtoken2, 2rewardtoken2 from tom9, 2aeusd token from tom9
      assert %{uco: 400_000_000, token: %{{"@AEUSDTOKEN", 0} => 200_000_000}} ==
               Account.get_balance("@Bob11")

      # @Tom9
      assert %{
               uco: 2_100_000_000,
               token: %{
                 {"@RewardToken1", 0} => 5_000_000_000,
                 {"@RewardToken2", 0} => 5_000_000_000
               }
             } == Account.get_balance("@Tom9")

      # from ray:2uco, reward_token1:50, reward_token2: 50
      assert %{
               uco: 200_000_000,
               token: %{
                 {"@RewardToken1", 0} => 5_000_000_000,
                 {"@RewardToken2", 0} => 5_000_000_000,
                 {"@RewardToken3", 0} => 5_000_000_000,
                 {"@RewardToken4", 0} => 200_000_000
               }
             } ==
               Account.get_balance("@Miner1")

      assert %{uco: 400_000_000, token: %{}} == Account.get_balance("@Leo0")
    end

    def get_reward_transactions() do
      [
        %Transaction{
          address: "@Ada1",
          type: :transfer,
          previous_public_key: "Ada0",
          validation_stamp: %ValidationStamp{
            timestamp: DateTime.utc_now(),
            ledger_operations: %LedgerOperations{
              transaction_movements: [
                %TransactionMovement{to: "@Tom7", amount: 3_400_000_000, type: :UCO},
                %TransactionMovement{
                  to: "@Bob5",
                  amount: 1_000_000_000,
                  type: {:token, "@AEUSDTOKEN", 0}
                },
                %TransactionMovement{
                  to: "@Tom7",
                  amount: 200_000_000,
                  type: {:token, "@RewardToken1", 0}
                },
                %TransactionMovement{
                  to: "@Bob11",
                  amount: 200_000_000,
                  type: {:token, "@RewardToken2", 0}
                }
              ],
              unspent_outputs: [
                %UnspentOutput{
                  from: "@Alen2",
                  amount: 200_000_000,
                  type: :UCO
                },
                %UnspentOutput{from: "@Dan2", amount: 1_900_000_000, type: :UCO},
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
        },
        %Transaction{
          address: "@Tom9",
          type: :transfer,
          previous_public_key: "@Tom3",
          validation_stamp: %ValidationStamp{
            timestamp: DateTime.utc_now(),
            ledger_operations: %LedgerOperations{
              transaction_movements: [
                %TransactionMovement{
                  to: "@Bob5",
                  amount: 100_000_000,
                  type: {:token, "@AEUSDTOKEN", 0}
                },
                %TransactionMovement{
                  to: "@Bob11",
                  amount: 200_000_000,
                  type: {:token, "@RewardToken1", 0}
                },
                %TransactionMovement{
                  to: "@Bob5",
                  amount: 200_000_000,
                  type: {:token, "@RewardToken2", 0}
                },
                %TransactionMovement{
                  to: "@Bob11",
                  amount: 200_000_000,
                  type: {:token, "@AEUSDTOKEN", 0}
                }
              ],
              unspent_outputs: [
                %UnspentOutput{
                  from: "@Alen2",
                  amount: 200_000_000,
                  type: :UCO
                },
                %UnspentOutput{from: "@Bob8", amount: 1_900_000_000, type: :UCO},
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
        },
        %Transaction{
          address: "@Miner1",
          type: :transfer,
          previous_public_key: "@Miner0",
          validation_stamp: %ValidationStamp{
            timestamp: DateTime.utc_now(),
            ledger_operations: %LedgerOperations{
              transaction_movements: [
                %TransactionMovement{
                  to: "@Leo0",
                  amount: 200_000_000,
                  type: {:token, "@RewardToken3", 0}
                },
                %TransactionMovement{
                  to: "@Leo0",
                  amount: 200_000_000,
                  type: {:token, "@RewardToken4", 0}
                }
              ],
              unspent_outputs: [
                %UnspentOutput{
                  from: "@Ray1",
                  amount: 200_000_000,
                  type: :UCO
                },
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
                },
                %UnspentOutput{
                  from: "@RewardToken3",
                  amount: 5_000_000_000,
                  type: {:token, "@RewardToken3", 0},
                  reward?: true
                },
                %UnspentOutput{
                  from: "@RewardToken4",
                  amount: 200_000_000,
                  type: {:token, "@RewardToken4", 0},
                  reward?: true
                }
              ]
            }
          }
        }
      ]
    end

    test "Node Rewards Should not be minted" do
      AccountTablesLoader.load_transaction(get_node_reward_txns())

      assert %{
               uco: 0,
               token: %{
                 {"@RewardToken1", 0} => 1_000_000_000,
                 {"@RewardToken2", 0} => 2_000_000_000
               }
             } == Account.get_balance("@Pool5")

      assert %{uco: 0, token: %{{"@RewardToken1", 0} => 200_000_000}} ==
               Account.get_balance("@Miner21")

      assert %{uco: 0, token: %{{"@RewardToken4", 0} => 200_000_000}} ==
               Account.get_balance("@Miner22")

      assert %{uco: 0, token: %{{"@RewardToken3", 0} => 200_000_000}} ==
               Account.get_balance("@Miner23")

      assert %{uco: 0, token: %{{"@RewardToken4", 0} => 200_000_000}} ==
               Account.get_balance("@Miner24")
    end

    def get_node_reward_txns() do
      %Transaction{
        address: "@Pool5",
        type: :node_rewards,
        previous_public_key: "@Pool4",
        validation_stamp: %ValidationStamp{
          timestamp: DateTime.utc_now(),
          ledger_operations: %LedgerOperations{
            transaction_movements: [
              %TransactionMovement{
                to: "@Miner21",
                amount: 200_000_000,
                type: {:token, "@RewardToken1", 0}
              },
              %TransactionMovement{
                to: "@Miner22",
                amount: 200_000_000,
                type: {:token, "@RewardToken4", 0}
              },
              %TransactionMovement{
                to: "@Miner23",
                amount: 200_000_000,
                type: {:token, "@RewardToken3", 0}
              },
              %TransactionMovement{
                to: "@Miner24",
                amount: 200_000_000,
                type: {:token, "@RewardToken4", 0}
              }
            ],
            unspent_outputs: [
              %UnspentOutput{
                from: "@RewardToken1",
                amount: 1_000_000_000,
                type: {:token, "@RewardToken1", 0},
                reward?: true
              },
              %UnspentOutput{
                from: "@RewardToken2",
                amount: 2_000_000_000,
                type: {:token, "@RewardToken2", 0},
                reward?: true
              }
            ]
          }
        }
      }
    end
  end
end
