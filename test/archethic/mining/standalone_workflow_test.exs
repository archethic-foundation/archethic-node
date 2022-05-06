defmodule Archethic.Mining.StandaloneWorkflowTest do
  use ArchethicCase

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias Archethic.Crypto

  alias Archethic.Mining.StandaloneWorkflow

  alias Archethic.P2P
  alias Archethic.P2P.Message.AcknowledgeStorage
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetUnspentOutputs
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Ping
  alias Archethic.P2P.Message.ReplicateTransactionChain
  alias Archethic.P2P.Message.UnspentOutputList
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionSummary

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

    unspent_outputs = [%UnspentOutput{from: "@Alice2", amount: 1_000_000_000, type: :UCO}]

    me = self()

    MockClient
    |> stub(:send_message, fn
      _, %Ping{}, _ ->
        {:ok, %Ok{}}

      _, %GetUnspentOutputs{}, _ ->
        {:ok,
         %UnspentOutputList{
           unspent_outputs: unspent_outputs
         }}

      _, %GetTransaction{}, _ ->
        {:ok, %NotFound{}}

      _, %ReplicateTransactionChain{transaction: tx}, _ ->
        tx_summary = TransactionSummary.from_transaction(tx)
        sig = Crypto.sign_with_last_node_key(TransactionSummary.serialize(tx_summary))

        {:ok,
         %AcknowledgeStorage{
           signature: sig
         }}

      _, %ReplicationAttestation{}, _ ->
        send(me, :transaction_replicated)
        {:ok, %Ok{}}
    end)

    tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)
    assert :ok = StandaloneWorkflow.run(transaction: tx)

    assert_receive :transaction_replicated
  end
end
