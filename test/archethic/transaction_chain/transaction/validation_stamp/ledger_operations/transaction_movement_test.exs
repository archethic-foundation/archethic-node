defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovementTest do
  use ArchethicCase

  import ArchethicCase
  import Mock
  alias Archethic.Reward
  alias Archethic.Reward.MemTables.RewardTokens

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  doctest TransactionMovement

  describe "resolve_addresses/2" do
    test "should resolve the movements" do
      transfer1_address = random_address()
      transfer2_address = random_address()
      transfer3_address = random_address()
      resolved1_address = random_address()
      resolved2_address = random_address()
      resolved3_address = random_address()
      token_address = random_address()

      resolved_addresses = %{
        transfer1_address => resolved1_address,
        transfer2_address => resolved2_address,
        transfer3_address => resolved3_address
      }

      assert [
               %TransactionMovement{
                 to: ^resolved1_address,
                 amount: 10,
                 type: :UCO
               },
               %TransactionMovement{
                 to: ^resolved2_address,
                 amount: 20,
                 type: :UCO
               },
               %TransactionMovement{
                 to: ^resolved3_address,
                 amount: 30,
                 type: :UCO
               },
               %TransactionMovement{
                 to: ^resolved1_address,
                 amount: 10,
                 type: {:token, ^token_address, 0}
               }
             ] =
               TransactionMovement.resolve_addresses(
                 [
                   %TransactionMovement{
                     to: transfer1_address,
                     amount: 10,
                     type: :UCO
                   },
                   %TransactionMovement{
                     to: transfer2_address,
                     amount: 20,
                     type: :UCO
                   },
                   %TransactionMovement{
                     to: transfer3_address,
                     amount: 30,
                     type: :UCO
                   },
                   %TransactionMovement{
                     to: transfer1_address,
                     amount: 10,
                     type: {:token, token_address, 0}
                   }
                 ],
                 resolved_addresses
               )
    end

    test "should resolve the movements with multiple time the same address" do
      transfer1_address = random_address()
      resolved1_address = random_address()
      token_address = random_address()

      resolved_addresses = %{
        transfer1_address => resolved1_address
      }

      assert [
               %TransactionMovement{
                 to: ^resolved1_address,
                 amount: 10,
                 type: :UCO
               },
               %TransactionMovement{
                 to: ^resolved1_address,
                 amount: 20,
                 type: :UCO
               },
               %TransactionMovement{
                 to: ^resolved1_address,
                 amount: 30,
                 type: :UCO
               },
               %TransactionMovement{
                 to: ^resolved1_address,
                 amount: 10,
                 type: {:token, ^token_address, 0}
               },
               %TransactionMovement{
                 to: ^resolved1_address,
                 amount: 30,
                 type: {:token, ^token_address, 0}
               }
             ] =
               TransactionMovement.resolve_addresses(
                 [
                   %TransactionMovement{
                     to: transfer1_address,
                     amount: 10,
                     type: :UCO
                   },
                   %TransactionMovement{
                     to: transfer1_address,
                     amount: 20,
                     type: :UCO
                   },
                   %TransactionMovement{
                     to: transfer1_address,
                     amount: 30,
                     type: :UCO
                   },
                   %TransactionMovement{
                     to: transfer1_address,
                     amount: 10,
                     type: {:token, token_address, 0}
                   },
                   %TransactionMovement{
                     to: transfer1_address,
                     amount: 30,
                     type: {:token, token_address, 0}
                   }
                 ],
                 resolved_addresses
               )
    end

    test "should drop movements without resolve address" do
      transfer1_address = random_address()
      transfer2_address = random_address()
      transfer3_address = random_address()
      token_address = random_address()

      resolved_addresses = %{}

      assert [] =
               TransactionMovement.resolve_addresses(
                 [
                   %TransactionMovement{
                     to: transfer1_address,
                     amount: 10,
                     type: :UCO
                   },
                   %TransactionMovement{
                     to: transfer2_address,
                     amount: 20,
                     type: :UCO
                   },
                   %TransactionMovement{
                     to: transfer3_address,
                     amount: 30,
                     type: :UCO
                   },
                   %TransactionMovement{
                     to: transfer1_address,
                     amount: 30,
                     type: {:token, token_address, 0}
                   }
                 ],
                 resolved_addresses
               )
    end
  end

  describe "aggregate/1" do
    test "should aggregate movement by type and recipient" do
      token1_address = random_address()
      token2_address = random_address()

      recipient1_address = random_address()
      recipient2_address = random_address()

      movements = [
        %TransactionMovement{
          to: recipient1_address,
          amount: 10,
          type: :UCO
        },
        %TransactionMovement{
          to: recipient1_address,
          amount: 20,
          type: :UCO
        },
        %TransactionMovement{
          to: recipient2_address,
          amount: 30,
          type: :UCO
        },
        %TransactionMovement{
          to: recipient1_address,
          amount: 10,
          type: {:token, token1_address, 0}
        },
        %TransactionMovement{
          to: recipient2_address,
          amount: 20,
          type: {:token, token1_address, 0}
        },
        %TransactionMovement{
          to: recipient2_address,
          amount: 30,
          type: {:token, token2_address, 0}
        },
        %TransactionMovement{
          to: recipient1_address,
          amount: 40,
          type: {:token, token1_address, 0}
        }
      ]

      expected_movements = [
        %TransactionMovement{
          to: recipient1_address,
          amount: 30,
          type: :UCO
        },
        %TransactionMovement{
          to: recipient2_address,
          amount: 30,
          type: :UCO
        },
        %TransactionMovement{
          to: recipient1_address,
          amount: 50,
          type: {:token, token1_address, 0}
        },
        %TransactionMovement{
          to: recipient2_address,
          amount: 20,
          type: {:token, token1_address, 0}
        },
        %TransactionMovement{
          to: recipient2_address,
          amount: 30,
          type: {:token, token2_address, 0}
        }
      ]

      aggregated_movements = TransactionMovement.aggregate(movements)

      # Order does not matter
      assert length(expected_movements) == length(aggregated_movements)
      assert Enum.all?(expected_movements, &Enum.member?(aggregated_movements, &1))
    end
  end

  describe "maybe_convert_reward" do
    setup do
      start_supervised!(RewardTokens)
      :ok
    end

    test "should convert MUCO movement to UCO movement" do
      address = random_address()
      reward_token_address = random_address()

      RewardTokens.add_reward_token_address(reward_token_address)

      movement = %TransactionMovement{
        to: address,
        amount: 30,
        type: {:token, reward_token_address, 0}
      }

      assert %TransactionMovement{to: address, amount: 30, type: :UCO} ==
               TransactionMovement.maybe_convert_reward(movement, :transfer)
    end

    test "should not convert MUCO movement to UCO movement if transaction in node_rewards" do
      address = random_address()
      reward_token_address = random_address()

      RewardTokens.add_reward_token_address(reward_token_address)

      movement = %TransactionMovement{
        to: address,
        amount: 30,
        type: {:token, reward_token_address, 0}
      }

      assert movement == TransactionMovement.maybe_convert_reward(movement, :node_rewards)
    end

    test "should not convert if token is not reward" do
      address = random_address()
      token_address = random_address()

      movement = %TransactionMovement{
        to: address,
        amount: 30,
        type: {:token, token_address, 0}
      }

      assert movement == TransactionMovement.maybe_convert_reward(movement, :transfer)
    end

    test "should not convert if movement is UCO" do
      address = random_address()

      movement = %TransactionMovement{to: address, amount: 30, type: :UCO}

      assert movement == TransactionMovement.maybe_convert_reward(movement, :transfer)
    end

    test "should not even check if tx type is token" do
      address = random_address()
      token_address = random_address()

      movement = %TransactionMovement{
        to: address,
        amount: 30,
        type: {:token, token_address, 0}
      }

      with_mock(Reward, is_reward_token?: fn _ -> false end) do
        assert movement == TransactionMovement.maybe_convert_reward(movement, :token)

        assert_not_called(Reward.is_reward_token?(:_))
      end
    end
  end
end
