defmodule Archethic.Reward.MemTables.MemLoadersTest do
  @moduledoc false
  use ArchethicCase, async: false

  alias Archethic.Reward
  alias Archethic.Reward.MemTables.RewardTokens
  alias Archethic.Reward.MemTablesLoader
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain
  import Mox

  @tx_type :mint_rewards
  @fields [:address, :type]

  describe "RewardTokens MEMTable: " do
    setup do
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

      start_supervised!(RewardTokens)
      start_supervised!(MemTablesLoader)
      :ok
    end

    test "RewardToken MemTable Should be alive" do
      assert Process.alive?(Process.whereis(RewardTokens))
    end

    test "Should Have loaded reward tokens" do
      Enum.each(TransactionChain.list_transactions_by_type(@tx_type, @fields), fn
        %Transaction{address: token_address, type: :mint_rewards} ->
          assert is_binary(token_address)
          assert true == Reward.is_reward_token?(token_address)
      end)
    end
  end
end
