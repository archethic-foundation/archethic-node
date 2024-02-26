defmodule Archethic.Mining.TransactionContextTest do
  use ArchethicCase

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetUnspentOutputs
  alias Archethic.P2P.Message.Ping
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.UnspentOutputList
  alias Archethic.P2P.Node

  alias Archethic.Mining.TransactionContext

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  doctest TransactionContext

  import Mox

  setup do
    P2P.add_and_connect_node(%Node{
      first_public_key: Crypto.last_node_public_key(),
      network_patch: "AAA",
      available?: false
    })

    :ok
  end

  describe "get/5" do
    test "should get the context of the transaction and involved nodes" do
      MockClient
      |> stub(:send_message, fn
        _, %GetTransaction{address: "@Alice1"}, _ ->
          {:ok, %Transaction{}}

        _, %Ping{}, _ ->
          {:ok, %Ok{}}

        _, %GetUnspentOutputs{address: "@Alice1"}, _ ->
          {:ok,
           %UnspentOutputList{
             unspent_outputs: [
               %VersionedUnspentOutput{
                 unspent_output: %UnspentOutput{
                   from: "@Bob3",
                   amount: 1_000_000_000,
                   type: :UCO,
                   timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
                 },
                 protocol_version: 1
               }
             ]
           }}
      end)

      node1 = %Node{
        last_public_key: "key1",
        first_public_key: "key1",
        ip: {127, 0, 0, 1},
        port: 3002,
        available?: true,
        geo_patch: "BCE",
        network_patch: "BCE",
        authorized?: true,
        authorization_date: DateTime.utc_now()
      }

      node2 = %Node{
        last_public_key: "key2",
        first_public_key: "key2",
        ip: {127, 0, 0, 1},
        port: 3003,
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA",
        authorized?: true,
        authorization_date: DateTime.utc_now()
      }

      node3 = %Node{
        last_public_key: "key3",
        first_public_key: "key3",
        ip: {127, 0, 0, 1},
        port: 3005,
        available?: true,
        geo_patch: "CDE",
        network_patch: "CDE",
        authorized?: true,
        authorization_date: DateTime.utc_now()
      }

      P2P.add_and_connect_node(node1)
      P2P.add_and_connect_node(node2)
      P2P.add_and_connect_node(node3)

      assert {%Transaction{}, [%VersionedUnspentOutput{}], _, <<1::1, 1::1>>, <<1::1, 1::1>>,
              <<1::1, 1::1>>} =
               TransactionContext.get("@Alice1", "@Alice1", ["key1", "key2"], ["key1", "key2"], [
                 "key2",
                 "key1"
               ])
    end
  end
end
