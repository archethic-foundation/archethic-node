defmodule Archethic.Reward.MemTablesLoaderTest do
  @moduledoc false
  use ArchethicCase

  alias Archethic.Reward
  alias Archethic.Reward.MemTables.RewardTokens
  alias Archethic.Reward.MemTablesLoader, as: RewardTableLoader
  import Mox

  @tx_type :mint_rewards
  @fields [:address, :type]

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  describe "RewardTokens MEMTable: " do
    setup do
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

      start_supervised!(RewardTokens)
      start_supervised!(RewardTableLoader)

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
