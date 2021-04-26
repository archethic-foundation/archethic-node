defmodule Uniris.Mining.TransactionContext.DataFetcherTest do
  use UnirisCase

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetP2PView
  alias Uniris.P2P.Message.GetTransaction
  alias Uniris.P2P.Message.GetUnspentOutputs
  alias Uniris.P2P.Message.NotFound
  alias Uniris.P2P.Message.P2PView
  alias Uniris.P2P.Message.UnspentOutputList
  alias Uniris.P2P.Node

  alias Uniris.Mining.TransactionContext.DataFetcher

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  import Mox

  setup do
    P2P.add_node(%Node{
      first_public_key: Crypto.node_public_key(),
      available?: false,
      network_patch: "AAA"
    })

    :ok
  end

  describe "fetch_previous_transaction/2" do
    test "should return the previous transaction and node involve if exists" do
      stub(MockClient, :send_message, fn _, %GetTransaction{} ->
        {:ok, %Transaction{}}
      end)

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key2",
        network_patch: "AAA"
      }

      P2P.add_node(node)

      assert {:ok, %Transaction{}, %Node{ip: {127, 0, 0, 1}}} =
               DataFetcher.fetch_previous_transaction("@Alice2", [node])
    end

    test "should return nil and node node involved if not exists" do
      stub(MockClient, :send_message, fn _, %GetTransaction{} ->
        {:ok, %NotFound{}}
      end)

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key2",
        network_patch: "AAA"
      }

      P2P.add_node(node)

      assert {:error, :not_found} = DataFetcher.fetch_previous_transaction("@Alice2", [node])
    end
  end

  describe "fetch_unspent_outputs/2" do
    test "should return the confirmed unspent outputs and nodes involved if exists" do
      unspent_output = %Transaction{
        validation_stamp: %ValidationStamp{
          ledger_operations: %LedgerOperations{
            transaction_movements: [
              %TransactionMovement{to: "@Alice2", amount: 10.0, type: :UCO}
            ]
          }
        }
      }

      MockClient
      |> stub(:send_message, fn
        _, %GetUnspentOutputs{} ->
          {:ok,
           %UnspentOutputList{
             unspent_outputs: [%UnspentOutput{from: "@Bob3", amount: 10, type: :UCO}]
           }}

        _, %GetTransaction{address: "@Bob3"} ->
          {:ok, unspent_output}
      end)

      node1 = %Node{
        last_public_key: "key1",
        first_public_key: "key1",
        ip: {127, 0, 0, 1},
        port: 3002,
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA"
      }

      P2P.add_node(node1)

      {:ok, [%UnspentOutput{from: "@Bob3", amount: 10, type: :UCO}],
       [%Node{last_public_key: "key1"}]} =
        DataFetcher.fetch_unspent_outputs("@Alice2", [node1], true)
    end

    test "should return the unspent outputs and nodes involved if exists" do
      MockClient
      |> stub(:send_message, fn
        _, %GetUnspentOutputs{} ->
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
        network_patch: "AAA"
      }

      P2P.add_node(node1)

      {:ok, [%UnspentOutput{from: "@Bob3", amount: 10, type: :UCO}],
       [%Node{last_public_key: "key1"}]} =
        DataFetcher.fetch_unspent_outputs("@Alice2", [node1], false)
    end

    test "should return an empty list of unspent outputs and nodes involved if not exists" do
      MockClient
      |> stub(:send_message, fn _, %GetUnspentOutputs{} ->
        {:ok, %UnspentOutputList{unspent_outputs: []}}
      end)

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        network_patch: "AAA"
      }

      P2P.add_node(node)

      assert {:ok, [], []} = DataFetcher.fetch_unspent_outputs("@Alice2", [node])
    end
  end

  describe "fetch_p2p_view/2" do
    test "should retrieve the P2P view for a list of node public keys" do
      stub(MockClient, :send_message, fn _, %GetP2PView{} ->
        {:ok, %P2PView{nodes_view: <<1::1, 1::1>>}}
      end)

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key2",
        network_patch: "AAA"
      }

      P2P.add_node(node)

      assert {:ok, <<1::1, 1::1>>, %Node{first_public_key: "key1"}} =
               DataFetcher.fetch_p2p_view(["key2", "key3"], [node])
    end
  end
end
