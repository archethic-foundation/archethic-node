defmodule Archethic.Mining.StandaloneWorkflowTest do
  use ArchethicCase
  import ArchethicCase

  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
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

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionSummary

  alias Archethic.TransactionFactory
  import Mox

  test "run/1 should auto validate the transaction and request storage" do
    start_supervised!({BeaconSlotTimer, interval: "0 * * * * * *"})
    start_supervised!({BeaconSummaryTimer, interval: "0 * * * * *"})

    P2P.add_and_connect_node(new_node())

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
          nil -> {:ok, %NotFound{}}
          tx -> {:ok, TransactionSummary.from_transaction(tx)}
        end

      _, %GetGenesisAddress{}, _ ->
        {:ok,
         %GenesisAddress{address: Transaction.previous_address(tx), timestamp: DateTime.utc_now()}}

      _, %ValidateTransaction{transaction: tx}, _ ->
        Agent.update(agent_pid, fn _ -> tx end)
        send(me, {:cross_replication_stamp, tx})
        {:ok, %Ok{}}

      _, %ReplicatePendingTransactionChain{}, _ ->
        tx = Agent.get(agent_pid, & &1)
        tx_summary = TransactionSummary.from_transaction(tx)
        sig = Crypto.sign_with_first_node_key(TransactionSummary.serialize(tx_summary))

        send(me, {:ack_replication, sig, Crypto.first_node_public_key()})

      _, %ReplicationAttestationMessage{}, _ ->
        send(me, :transaction_replicated)
        {:ok, %Ok{}}
    end)

    assert {:ok, pid} =
             StandaloneWorkflow.start_link(
               transaction: tx,
               welcome_node: P2P.get_node_info!(Crypto.first_node_public_key()),
               ref_timestamp: DateTime.utc_now()
             )

    receive do
      {:cross_replication_stamp, tx} ->
        cross_stamp = CrossValidationStamp.sign(%CrossValidationStamp{}, tx.validation_stamp)
        send(pid, {:add_cross_validation_stamp, cross_stamp, Crypto.first_node_public_key()})
    after
      1000 -> :skip
    end

    receive do
      {:ack_replication, sig, public_key} ->
        send(pid, {:ack_replication, sig, public_key})
    after
      1000 -> :skip
    end

    assert_receive :transaction_replicated
  end
end
