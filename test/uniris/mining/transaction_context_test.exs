defmodule Uniris.Mining.TransactionContextTest do
  use UnirisCase

  alias Uniris.Crypto

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

  setup do
    P2P.add_node(%Node{
      first_public_key: Crypto.node_public_key(),
      network_patch: "AAA",
      available?: false
    })

    :ok
  end

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
        _, %GetTransaction{address: "@Bob3"} ->
          {:ok, unspent_output}

        _, %GetTransaction{address: "@Alice1"} ->
          {:ok, unspent_output}

        _, %GetP2PView{} ->
          {:ok, %P2PView{nodes_view: <<1::1, 1::1>>}}

        _, %GetUnspentOutputs{address: "@Alice1"} ->
          {:ok,
           %UnspentOutputList{
             unspent_outputs: [%UnspentOutput{from: "@Bob3", amount: 10.0, type: :UCO}]
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
