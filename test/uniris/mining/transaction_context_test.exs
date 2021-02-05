defmodule Uniris.Mining.TransactionContextTest do
  use UnirisCase

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetP2PView
  alias Uniris.P2P.Message.GetTransaction
  alias Uniris.P2P.Message.GetUnspentOutputs
  alias Uniris.P2P.Message.P2PView
  alias Uniris.P2P.Message.UnspentOutputList
  alias Uniris.P2P.Node

  alias Uniris.Mining.TransactionContext

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  doctest TransactionContext

  import Mox

  describe "get/5" do
    test "should get the context of the transaction and involved nodes" do
      unspent_output = %Transaction{
        validation_stamp: %ValidationStamp{
          ledger_operations: %LedgerOperations{
            transaction_movements: [
              %TransactionMovement{to: "@Alice1", amount: 10.0, type: :UCO}
            ]
          }
        }
      }

      MockClient
      |> stub(:send_message, fn
        %Node{port: 3003}, %GetUnspentOutputs{address: "@Alice1"} ->
          %UnspentOutputList{
            unspent_outputs: [%UnspentOutput{from: "@Bob3", amount: 10.0, type: :UCO}]
          }

        %Node{port: 3002}, %GetUnspentOutputs{address: "@Alice1"} ->
          Process.sleep(200)

          %UnspentOutputList{
            unspent_outputs: [%UnspentOutput{from: "@Bob3", amount: 10.0, type: :UCO}]
          }

        3005, %GetUnspentOutputs{address: "@Alice1"} ->
          Process.sleep(400)

          %UnspentOutputList{
            unspent_outputs: [%UnspentOutput{from: "@Bob3", amount: 10.0, type: :UCO}]
          }

        %Node{port: 3003}, %GetP2PView{} ->
          %P2PView{nodes_view: <<1::1, 1::1>>}

        %Node{port: 3002}, %GetP2PView{} ->
          Process.sleep(200)
          %P2PView{nodes_view: <<1::1, 1::1>>}

        %Node{port: 3005}, %GetP2PView{} ->
          Process.sleep(400)
          %P2PView{nodes_view: <<1::1, 1::1>>}

        %Node{port: 3002}, %GetTransaction{address: "@Bob3"} ->
          unspent_output

        %Node{port: 3003}, %GetTransaction{address: "@Bob3"} ->
          Process.sleep(200)
          unspent_output

        %Node{port: 3005}, %GetTransaction{address: "@Bob3"} ->
          Process.sleep(500)
          unspent_output

        %Node{port: 3003}, %GetTransaction{address: "@Alice1"} ->
          Process.sleep(300)
          %Transaction{}

        %Node{port: 3005}, %GetTransaction{address: "@Alice1"} ->
          %Transaction{}

        %Node{port: 3002}, %GetTransaction{address: "@Alice1"} ->
          Process.sleep(200)
          %Transaction{}
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

      node3 = %Node{
        last_public_key: "key3",
        first_public_key: "key3",
        ip: {127, 0, 0, 1},
        port: 3005,
        available?: true,
        geo_patch: "AAA"
      }

      P2P.add_node(node1)
      P2P.add_node(node2)
      P2P.add_node(node3)

      assert {%Transaction{}, [%UnspentOutput{}], involved_nodes, <<1::1, 1::1>>, <<1::1, 1::1>>,
              <<1::1, 1::1>>} =
               TransactionContext.get("@Alice1", ["key1", "key2"], ["key1", "key2"], [
                 "key1",
                 "key2"
               ])

      assert involved_nodes
             |> Enum.map(& &1.first_public_key)
             |> Enum.all?(&(&1 in ["key1", "key2", "key3"]))
    end
  end
end
