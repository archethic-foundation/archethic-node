defmodule ArchEthic.Mining.StandaloneWorkflowTest do
  use ArchEthicCase

  alias ArchEthic.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias ArchEthic.Crypto

  alias ArchEthic.Mining.StandaloneWorkflow

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.GetP2PView
  alias ArchEthic.P2P.Message.GetTransaction
  alias ArchEthic.P2P.Message.GetUnspentOutputs
  alias ArchEthic.P2P.Message.NotFound
  alias ArchEthic.P2P.Message.Ok
  alias ArchEthic.P2P.Message.P2PView
  alias ArchEthic.P2P.Message.ReplicateTransaction
  alias ArchEthic.P2P.Message.UnspentOutputList
  alias ArchEthic.P2P.Node

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias ArchEthic.TransactionChain.TransactionData

  import Mox

  test "run/1 should auto validate the transaction and request storage" do
    start_supervised!({BeaconSlotTimer, interval: "0 * * * * * *"})

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      last_public_key: Crypto.last_node_public_key(),
      first_public_key: Crypto.last_node_public_key(),
      geo_patch: "AAA",
      network_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-1),
      reward_address: :crypto.strong_rand_bytes(32)
    })

    unspent_outputs = [%UnspentOutput{from: "@Alice2", amount: 10.0, type: :UCO}]

    me = self()

    MockClient
    |> stub(:send_message, fn
      _, %GetP2PView{} ->
        {:ok, %P2PView{nodes_view: <<1::1>>}}

      _, %GetUnspentOutputs{} ->
        {:ok, %UnspentOutputList{unspent_outputs: unspent_outputs}}

      _, %GetTransaction{} ->
        {:ok, %NotFound{}}

      _, %ReplicateTransaction{} ->
        send(me, :transaction_replicated)
        {:ok, %Ok{}}
    end)

    tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)
    assert :ok = StandaloneWorkflow.run(transaction: tx)

    assert_receive :transaction_replicated
  end
end
