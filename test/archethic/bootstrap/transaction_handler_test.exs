defmodule Archethic.Bootstrap.TransactionHandlerTest do
  use ArchethicCase

  @moduletag :capture_log

  alias Archethic.Bootstrap.TransactionHandler

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.NewTransaction
  alias Archethic.P2P.Message.Ok

  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData

  import Mox

  test "create_node_transaction/4 should create transaction with ip and port encoded in the content" do
    assert %Transaction{
             data: %TransactionData{
               content: content
             }
           } =
             TransactionHandler.create_node_transaction(
               {127, 0, 0, 1},
               3000,
               4000,
               :tcp,
               <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
             )

    assert {:ok, {127, 0, 0, 1}, 3000, 4000, :tcp, _reward_address, _origin_public_key, _cert,
            mining_public_key} = Node.decode_transaction_content(content)

    assert Archethic.Crypto.mining_node_public_key() == mining_public_key
  end

  test "send_transaction/2 should send the transaction to a welcome node" do
    node = %Node{
      ip: {80, 10, 101, 202},
      port: 3005,
      http_port: 4000,
      first_public_key: "key1",
      last_public_key: "key1",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      enrollment_date: DateTime.utc_now()
    }

    :ok = P2P.add_and_connect_node(node)

    tx =
      TransactionHandler.create_node_transaction(
        {127, 0, 0, 1},
        3000,
        4000,
        :tcp,
        "00610F69B6C5C3449659C99F22956E5F37AA6B90B473585216CF4931DAF7A0AB45"
      )

    validated_transaction = %Transaction{
      tx
      | validation_stamp: %ValidationStamp{},
        cross_validation_stamps: [%{}]
    }

    MockClient
    |> stub(:send_message, fn
      _, %NewTransaction{}, _ ->
        {:ok, %Ok{}}

      _, %GetTransaction{}, _ ->
        {:ok, validated_transaction}
    end)

    assert {:ok, ^validated_transaction} = TransactionHandler.send_transaction(tx, [node])
  end
end
