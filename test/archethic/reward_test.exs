defmodule Archethic.RewardTest do
  use ArchethicCase
  use ExUnitProperties

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetUnspentOutputs
  alias Archethic.P2P.Message.UnspentOutputList
  alias Archethic.P2P.Node

  alias Archethic.Reward
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  import ArchethicCase
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
    address = random_address()
    token_address1 = random_address()
    token_address2 = random_address()

    :persistent_term.put(:reward_gen_addr, address)

    reward_amount = Reward.validation_nodes_reward()

    reward_amount2 = reward_amount - 10

    timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    unspent_outputs1 = %UnspentOutput{
      from: random_address(),
      amount: reward_amount * 2,
      type: {:token, token_address1, 0},
      timestamp: timestamp
    }

    unspent_outputs2 = %UnspentOutput{
      from: random_address(),
      amount: reward_amount2,
      type: {:token, token_address2, 0},
      timestamp: timestamp
    }

    utxos =
      [unspent_outputs1, unspent_outputs2]
      |> VersionedUnspentOutput.wrap_unspent_outputs(current_protocol_version())

    MockClient
    |> expect(:send_message, fn _, %GetUnspentOutputs{}, _ ->
      {:ok, %UnspentOutputList{unspent_outputs: utxos}}
    end)

    assert [
             %Transfer{
               amount: 10,
               to: "ADR1",
               token_address: ^token_address1
             },
             %Transfer{
               amount: ^reward_amount2,
               to: "ADR1",
               token_address: ^token_address2
             },
             %Transfer{
               amount: ^reward_amount,
               to: "ADR2",
               token_address: ^token_address1
             }
           ] = Reward.get_transfers()

    :persistent_term.erase(:reward_gen_addr)
  end
end
