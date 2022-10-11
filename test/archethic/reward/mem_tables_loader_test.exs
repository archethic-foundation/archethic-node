defmodule Archethic.Reward.MemTablesLoaderTest do
  @moduledoc false
  use ArchethicCase

  import Mox

  @tx_type :mint_rewards
  @fields [:address, :type]

  alias Archethic.{
    Crypto,
    Reward,
    Reward.MemTables.RewardTokens,
    TransactionChain,
    P2P,
    P2P.Node
  }

  alias Archethic.TransactionChain.{
    Transaction,
    Transaction.ValidationStamp,
    Transaction.ValidationStamp.LedgerOperations
  }

  alias Archethic.Reward.MemTablesLoader, as: RewardTableLoader

  describe "RewardTokens MEMTable: " do
    setup do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3002,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA",
        available?: true
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
