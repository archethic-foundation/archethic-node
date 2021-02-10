defmodule Uniris.Mining.TransactionContext.DataFetcherTest do
  use UnirisCase

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

  describe "fetch_previous_transaction/2" do
    test "should return the previous transaction and node involve if exists" do
      stub(MockClient, :send_message, fn _, %GetTransaction{} ->
        %Transaction{}
      end)

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key2"
      }

      P2P.add_node(node)

      assert {:ok, %Transaction{}, %Node{ip: {127, 0, 0, 1}}} =
               DataFetcher.fetch_previous_transaction("@Alice2", [node])
    end

    test "should return nil and node node involved if not exists" do
      stub(MockClient, :send_message, fn _, %GetTransaction{} ->
        %NotFound{}
      end)

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key2"
      }

      P2P.add_node(node)

      assert {:error, :not_found} = DataFetcher.fetch_previous_transaction("@Alice2", [node])
    end

    test "should retrieve from the first node replying" do
      stub(MockClient, :send_message, fn
        %Node{port: 5000}, %GetTransaction{} ->
          %Transaction{}

        %Node{port: 3000}, %GetTransaction{} ->
          Process.sleep(300)
          %Transaction{}
      end)

      node1 = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1"
      }

      P2P.add_node(node1)

      node2 = %Node{
        ip: {127, 0, 0, 1},
        port: 5000,
        first_public_key: "key2",
        last_public_key: "key2"
      }

      P2P.add_node(node2)

      assert {:ok, %Transaction{}, %Node{port: 5000}} =
               DataFetcher.fetch_previous_transaction("@Alice2", [node1, node2])
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
          %UnspentOutputList{
            unspent_outputs: [%UnspentOutput{from: "@Bob3", amount: 10, type: :UCO}]
          }

        _, %GetTransaction{address: "@Bob3"} ->
          unspent_output
      end)

      node1 = %Node{
        last_public_key: "key1",
        first_public_key: "key1",
        ip: {127, 0, 0, 1},
        port: 3002,
        available?: true,
        geo_patch: "AAA"
      }

      P2P.add_node(node1)

      {[%UnspentOutput{from: "@Bob3", amount: 10, type: :UCO}], [%Node{last_public_key: "key1"}]} =
        DataFetcher.fetch_unspent_outputs("@Alice2", [node1], true)
    end

    test "should return the unspent outputs and nodes involved if exists" do
      MockClient
      |> stub(:send_message, fn _, %GetUnspentOutputs{} ->
        %UnspentOutputList{
          unspent_outputs: [%UnspentOutput{from: "@Bob3", amount: 10, type: :UCO}]
        }
      end)

      node1 = %Node{
        last_public_key: "key1",
        first_public_key: "key1",
        ip: {127, 0, 0, 1},
        port: 3002,
        available?: true,
        geo_patch: "AAA"
      }

      P2P.add_node(node1)

      {[%UnspentOutput{from: "@Bob3", amount: 10, type: :UCO}], [%Node{last_public_key: "key1"}]} =
        DataFetcher.fetch_unspent_outputs("@Alice2", [node1], false)
    end

    test "should return an empty list of unspent outputs and nodes involved if not exists" do
      MockClient
      |> stub(:send_message, fn _, %GetUnspentOutputs{} ->
        %UnspentOutputList{unspent_outputs: []}
      end)

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1"
      }

      P2P.add_node(node)

      assert {[], []} = DataFetcher.fetch_unspent_outputs("@Alice2", [node])
    end

    test "should retrieve from the first node replying" do
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
        %Node{port: 3003}, %GetUnspentOutputs{address: "@Alice2"} ->
          %UnspentOutputList{
            unspent_outputs: [%UnspentOutput{from: "@Bob3", amount: 10.0, type: :UCO}]
          }

        %Node{port: 3002}, %GetUnspentOutputs{address: "@Alice2"} ->
          Process.sleep(200)

          %UnspentOutputList{
            unspent_outputs: [%UnspentOutput{from: "@Bob3", amount: 10.0, type: :UCO}]
          }

        %Node{port: 3002}, %GetTransaction{address: "@Bob3"} ->
          unspent_output

        %Node{port: 3003}, %GetTransaction{address: "@Bob3"} ->
          Process.sleep(200)
          unspent_output
      end)

      node1 = %Node{
        last_public_key: "key1",
        first_public_key: "key1",
        ip: {127, 0, 0, 1},
        port: 3002,
        available?: true,
        geo_patch: "BCE"
      }

      node2 = %Node{
        last_public_key: "key2",
        first_public_key: "key2",
        ip: {127, 0, 0, 1},
        port: 3003,
        available?: true,
        geo_patch: "AAA"
      }

      P2P.add_node(node1)
      P2P.add_node(node2)

      {[%UnspentOutput{from: "@Bob3", amount: 10.0, type: :UCO}],
       [%Node{last_public_key: "key2"}, %Node{last_public_key: "key1"}]} =
        DataFetcher.fetch_unspent_outputs("@Alice2", [node1, node2], true)
    end
  end

  describe "fetch_p2p_view/2" do
    test "should retrieve the P2P view for a list of node public keys" do
      stub(MockClient, :send_message, fn _, %GetP2PView{} ->
        %P2PView{nodes_view: <<1::1, 1::1>>}
      end)

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key2"
      }

      P2P.add_node(node)

      assert {<<1::1, 1::1>>, %Node{first_public_key: "key1"}} =
               DataFetcher.fetch_p2p_view(["key2", "key3"], [node])
    end

    test "should retrieve the P2P view for a list of node public keys from the first reply" do
      stub(MockClient, :send_message, fn
        %Node{port: 3002}, %GetP2PView{} ->
          Process.sleep(200)
          %P2PView{nodes_view: <<1::1, 1::1>>}

        %Node{port: 3005}, %GetP2PView{} ->
          %P2PView{nodes_view: <<1::1, 1::1>>}
      end)

      node1 = %Node{
        ip: {127, 0, 0, 1},
        port: 3002,
        first_public_key: "key1",
        last_public_key: "key1"
      }

      node2 = %Node{
        ip: {127, 0, 0, 1},
        port: 3005,
        first_public_key: "key2",
        last_public_key: "key2"
      }

      P2P.add_node(node1)
      P2P.add_node(node2)

      assert {<<1::1, 1::1>>, %Node{first_public_key: "key2"}} =
               DataFetcher.fetch_p2p_view(["key2", "key3"], [node1, node2])
    end
  end
end
