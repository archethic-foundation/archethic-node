defmodule Uniris.Mining.StandaloneWorkflowTest do
  use UnirisCase

  alias Uniris.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias Uniris.Crypto

  alias Uniris.Mining.StandaloneWorkflow

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetP2PView
  alias Uniris.P2P.Message.GetTransaction
  alias Uniris.P2P.Message.GetUnspentOutputs
  alias Uniris.P2P.Message.NotFound
  alias Uniris.P2P.Message.Ok
  alias Uniris.P2P.Message.P2PView
  alias Uniris.P2P.Message.ReplicateTransaction
  alias Uniris.P2P.Message.UnspentOutputList
  alias Uniris.P2P.Node

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Uniris.TransactionChain.TransactionData

  import Mox

  test "run/1 should auto validate the transaction and request storage it" do
    start_supervised!({BeaconSlotTimer, interval: "0 * * * * * *", trigger_offset: 0})

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      last_public_key: Crypto.node_public_key(),
      first_public_key: Crypto.node_public_key(),
      geo_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-1)
    })

    unspent_outputs = [%UnspentOutput{from: "@Alice2", amount: 10.0}]

    me = self()

    MockTransport
    |> stub(:send_message, fn
      _, _, %GetUnspentOutputs{} ->
        {:ok, %UnspentOutputList{unspent_outputs: unspent_outputs}}

      _, _, %GetP2PView{} ->
        {:ok, %P2PView{nodes_view: <<1::1>>}}

      _, _, %GetTransaction{} ->
        {:ok, %NotFound{}}

      _, _, %ReplicateTransaction{} ->
        send(me, :transaction_replicated)
        {:ok, %Ok{}}
    end)

    tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)
    assert :ok = StandaloneWorkflow.run(transaction: tx)

    assert_received :transaction_replicated
  end
end
