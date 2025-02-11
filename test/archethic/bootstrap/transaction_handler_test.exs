defmodule Archethic.Bootstrap.TransactionHandlerTest do
  use ArchethicCase

  @moduletag :capture_log

  alias Archethic.Bootstrap.TransactionHandler

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.NewTransaction
  alias Archethic.P2P.Message.Ok

  alias Archethic.P2P.Node
  alias Archethic.P2P.NodeConfig

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData

  import ArchethicCase
  import Mox

  @geo_patch_max_update_time Application.compile_env!(:archethic, :geopatch_update_time)

  test "create_node_transaction/4 should create transaction with ip, geopatch and port encoded in the content" do
    now = DateTime.utc_now()

    node_config = %NodeConfig{
      ip: {127, 0, 0, 1},
      port: 3000,
      http_port: 4000,
      transport: :tcp,
      reward_address: random_address(),
      origin_public_key: random_public_key(),
      origin_certificate: :crypto.strong_rand_bytes(64),
      mining_public_key: <<3::8, 2::8, :crypto.strong_rand_bytes(48)::binary>>,
      geo_patch: "AAA",
      geo_patch_update:
        DateTime.add(now, @geo_patch_max_update_time, :millisecond) |> DateTime.truncate(:second)
    }

    assert %Transaction{data: %TransactionData{content: content}} =
             TransactionHandler.create_node_transaction(node_config, now)

    assert {:ok, node_config} == Node.decode_transaction_content(content)
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

    node_config = %NodeConfig{
      ip: {127, 0, 0, 1},
      port: 3000,
      http_port: 4000,
      transport: :tcp,
      reward_address: random_address(),
      origin_public_key: random_public_key(),
      origin_certificate: :crypto.strong_rand_bytes(64),
      mining_public_key: <<3::8, 2::8, :crypto.strong_rand_bytes(48)::binary>>,
      geo_patch: "AAA"
    }

    tx = TransactionHandler.create_node_transaction(node_config)

    validated_transaction = %Transaction{
      tx
      | validation_stamp: %ValidationStamp{},
        cross_validation_stamps: [%{}]
    }

    MockClient
    |> stub(:send_message, fn
      _, %NewTransaction{}, _ -> {:ok, %Ok{}}
      _, %GetTransaction{}, _ -> {:ok, validated_transaction}
    end)

    assert {:ok, ^validated_transaction} = TransactionHandler.send_transaction(tx, [node])
  end
end
