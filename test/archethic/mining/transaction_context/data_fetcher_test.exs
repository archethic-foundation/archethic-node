defmodule Archethic.Mining.TransactionContext.DataFetcherTest do
  use ArchethicCase

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetUnspentOutputs
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Ping
  alias Archethic.P2P.Message.UnspentOutputList
  alias Archethic.P2P.Node

  alias Archethic.Mining.TransactionContext.DataFetcher

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  import Mox

  setup do
    P2P.add_and_connect_node(%Node{
      first_public_key: Crypto.last_node_public_key(),
      available?: false,
      network_patch: "AAA"
    })

    :ok
  end

  describe "fetch_previous_transaction/2" do
    test "should return the previous transaction and node involve if exists" do
      stub(MockClient, :send_message, fn _, %GetTransaction{}, _ ->
        {:ok, %Transaction{}}
      end)

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key2",
        network_patch: "AAA",
        authorized?: true,
        authorization_date: DateTime.utc_now()
      }

      P2P.add_and_connect_node(node)

      assert {:ok, %Transaction{}, %Node{ip: {127, 0, 0, 1}}} =
               DataFetcher.fetch_previous_transaction("@Alice2", [node])
    end

    test "should return nil and node node involved if not exists" do
      stub(MockClient, :send_message, fn _, %GetTransaction{}, _ ->
        {:ok, %NotFound{}}
      end)

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key2",
        network_patch: "AAA",
        authorized?: true,
        authorization_date: DateTime.utc_now()
      }

      P2P.add_and_connect_node(node)

      assert {:error, :not_found} = DataFetcher.fetch_previous_transaction("@Alice2", [node])
    end
  end

  test "should return the unspent outputs and nodes involved if exists" do
    MockClient
    |> stub(:send_message, fn
      _, %GetUnspentOutputs{}, _ ->
        {:ok,
         %UnspentOutputList{
           unspent_outputs: [%UnspentOutput{from: "@Bob3", amount: 10, type: :UCO}]
         }}
    end)

    node1 = %Node{
      last_public_key: "key1",
      first_public_key: "key1",
      ip: {127, 0, 0, 1},
      port: 3002,
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA",
      authorized?: true,
      authorization_date: DateTime.utc_now()
    }

    P2P.add_and_connect_node(node1)

    {:ok, [%UnspentOutput{from: "@Bob3", amount: 10, type: :UCO}], %Node{last_public_key: "key1"}} =
      DataFetcher.fetch_unspent_outputs("@Alice2", [node1])
  end

  describe "fetch_p2p_view/2" do
    test "should retrieve the P2P view for a list of node public keys" do
      stub(MockClient, :send_message, fn _, %Ping{}, _ ->
        {:ok, %Ok{}}
      end)

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key2",
        network_patch: "AAA",
        authorized?: true,
        authorization_date: DateTime.utc_now()
      }

      P2P.add_and_connect_node(node)

      assert %{"key2" => true, "key3" => false} = DataFetcher.fetch_p2p_view(["key2", "key3"])
    end
  end
end
