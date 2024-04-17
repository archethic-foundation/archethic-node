defmodule Archethic.Mining.StandaloneWorkflowTest do
  use ArchethicCase
  import ArchethicCase

  alias Archethic.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias Archethic.BeaconChain.SummaryTimer, as: BeaconSummaryTimer
  alias Archethic.Crypto

  alias Archethic.Mining.StandaloneWorkflow

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetGenesisAddress
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetTransactionSummary
  alias Archethic.P2P.Message.GetUnspentOutputs
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Ping
  alias Archethic.P2P.Message.ValidateTransaction
  alias Archethic.P2P.Message.ReplicatePendingTransactionChain
  alias Archethic.P2P.Message.UnspentOutputList
  alias Archethic.P2P.Message.ReplicationAttestationMessage
  alias Archethic.P2P.Message.GenesisAddress
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionSummary

  alias Archethic.TransactionFactory
  import Mox

  test "run/1 should auto validate the transaction and request storage" do
    start_supervised!({BeaconSlotTimer, interval: "0 * * * * * *"})
    start_supervised!({BeaconSummaryTimer, interval: "0 * * * * *"})

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      last_public_key: Crypto.last_node_public_key(),
      first_public_key: Crypto.first_node_public_key(),
      geo_patch: "AAA",
      network_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-1),
      reward_address: :crypto.strong_rand_bytes(32)
    })

    unspent_outputs = [
      %VersionedUnspentOutput{
        unspent_output: %UnspentOutput{
          from: "@Alice2",
          amount: 1_000_000_000,
          type: :UCO,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        },
        protocol_version: 1
      }
    ]

    me = self()

    tx =
      TransactionFactory.create_valid_transaction(
        [
          %UnspentOutput{
            type: :UCO,
            amount: 1_000_000_000,
            from: random_address(),
            timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
          }
        ],
        type: :data,
        content: "content"
      )

    {:ok, agent_pid} = Agent.start_link(fn -> nil end)

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

      _, %GetTransactionSummary{}, _ ->
        case Agent.get(agent_pid, & &1) do
          nil ->
            {:ok, %NotFound{}}

          tx ->
            tx_summary = TransactionSummary.from_transaction(tx, Transaction.previous_address(tx))
            {:ok, tx_summary}
        end

      _, %GetGenesisAddress{}, _ ->
        {:ok, %GenesisAddress{address: "@Alice0", timestamp: DateTime.utc_now()}}

      _, %ValidateTransaction{transaction: tx}, _ ->
        Agent.update(agent_pid, fn _ -> tx end)
        {:ok, %Ok{}}

      _, %ReplicatePendingTransactionChain{genesis_address: genesis_address}, _ ->
        tx = Agent.get(agent_pid, & &1)
        tx_summary = TransactionSummary.from_transaction(tx, genesis_address)
        sig = Crypto.sign_with_first_node_key(TransactionSummary.serialize(tx_summary))

        send(me, {:ack_replication, sig, Crypto.first_node_public_key()})

      _, %ReplicationAttestationMessage{}, _ ->
        send(me, :transaction_replicated)
        {:ok, %Ok{}}
    end)

    assert {:ok, pid} =
             StandaloneWorkflow.start_link(
               transaction: tx,
               welcome_node: P2P.get_node_info!(Crypto.last_node_public_key())
             )

    receive do
      {:ack_replication, sig, public_key} ->
        send(pid, {:ack_replication, sig, public_key})
    after
      3000 -> :skip
    end

    assert_receive :transaction_replicated
  end
end
