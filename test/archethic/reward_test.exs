defmodule Archethic.RewardTest do
  use ArchethicCase
  use ExUnitProperties

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.Reward
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.Account.MemTables.TokenLedger

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
end
