defmodule Archethic.SelfRepair.NotifierTest do
  use ArchethicCase

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.ReplicateTransaction
  alias Archethic.P2P.Node

  alias Archethic.SelfRepair.Notifier
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp

  import Mox

  test "when a node is becoming offline new nodes should receive transaction to replicate" do
    P2P.add_and_connect_node(%Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.first_node_public_key(),
      ip: {127, 0, 0, 1},
      port: 3000,
      authorized?: true,
      authorization_date: ~U[2022-02-01 00:00:00Z],
      geo_patch: "AAA"
    })

    P2P.add_and_connect_node(%Node{
      first_public_key: "node2",
      last_public_key: "node2",
      ip: {127, 0, 0, 1},
      port: 3001,
      authorized?: true,
      authorization_date: ~U[2022-02-01 00:00:00Z],
      geo_patch: "CCC"
    })

    P2P.add_and_connect_node(%Node{
      first_public_key: "node3",
      last_public_key: "node3",
      ip: {127, 0, 0, 1},
      port: 3002,
      authorized?: true,
      authorization_date: ~U[2022-02-03 00:00:00Z],
      geo_patch: "DDD"
    })

    {:ok, pid} = Notifier.start_link()

    MockDB
    |> expect(:list_transactions, fn _ ->
      [
        %Transaction{
          address: "@Alice1",
          type: :transfer,
          validation_stamp: %ValidationStamp{
            timestamp: ~U[2022-02-01 12:54:00Z]
          }
        }
      ]
    end)

    me = self()

    MockClient
    |> expect(:send_message, fn %Node{first_public_key: "node3"},
                                %ReplicateTransaction{
                                  transaction: %Transaction{address: "@Alice1"}
                                },
                                _ ->
      send(me, :tx_replicated)
      %Ok{}
    end)

    send(
      pid,
      {:node_update,
       %Node{
         first_public_key: "node2",
         available?: false,
         authorized?: true,
         authorization_date: ~U[2022-02-01 00:00:00Z]
       }}
    )

    assert_receive :tx_replicated
  end
end
