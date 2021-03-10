defmodule Uniris.SelfRepair.Sync.BeaconSummaryHandler.TransactionHandlerTest do
  use UnirisCase

  alias Uniris.BeaconChain
  alias Uniris.BeaconChain.Slot.TransactionSummary
  alias Uniris.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias Uniris.BeaconChain.Subset, as: BeaconSubset

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Batcher
  alias Uniris.P2P.Message.BatchRequests
  alias Uniris.P2P.Message.BatchResponses
  alias Uniris.P2P.Message.GetTransaction
  alias Uniris.P2P.Message.GetTransactionChain
  alias Uniris.P2P.Message.GetTransactionInputs
  alias Uniris.P2P.Message.TransactionInputList
  alias Uniris.P2P.Message.TransactionList
  alias Uniris.P2P.Node

  alias Uniris.SelfRepair.Sync.BeaconSummaryHandler.TransactionHandler

  alias Uniris.TransactionFactory

  alias Uniris.TransactionChain.TransactionInput

  doctest TransactionHandler

  import Mox

  setup do
    Enum.each(BeaconChain.list_subsets(), &BeaconSubset.start_link(subset: &1))
    start_supervised!({BeaconSlotTimer, interval: "0 * * * * * *"})
    start_supervised!(Batcher)

    welcome_node = %Node{
      first_public_key: "key1",
      last_public_key: "key1",
      available?: true,
      geo_patch: "BBB",
      network_patch: "BBB"
    }

    coordinator_node = %Node{
      first_public_key: Crypto.node_public_key(0),
      last_public_key: Crypto.node_public_key(),
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-10),
      geo_patch: "AAA",
      network_patch: "AAA"
    }

    storage_nodes = [
      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key3",
        last_public_key: "key3",
        available?: true,
        geo_patch: "BBB",
        network_patch: "BBB"
      }
    ]

    Enum.each(storage_nodes, &P2P.add_node(&1))

    P2P.add_node(welcome_node)
    P2P.add_node(coordinator_node)

    {:ok,
     %{
       welcome_node: welcome_node,
       coordinator_node: coordinator_node,
       storage_nodes: storage_nodes
     }}
  end

  test "download_transaction?/1 should return true when the node is a chain storage node" do
    assert true =
             TransactionHandler.download_transaction?(%TransactionSummary{
               address: "@Alice2"
             })
  end

  test "download_transaction/2 should download the transaction", context do
    me = self()

    inputs = [
      %TransactionInput{from: "@Alice2", amount: 10.0, type: :UCO, timestamp: DateTime.utc_now()}
    ]

    tx = TransactionFactory.create_valid_transaction(context, inputs)

    MockDB
    |> stub(:write_transaction_chain, fn _ ->
      send(me, :transaction_replicated)
      :ok
    end)

    MockClient
    |> stub(:send_message, fn
      _, %BatchRequests{requests: [%GetTransaction{}]}, _ ->
        {:ok, %BatchResponses{responses: [{0, tx}]}}

      _, %BatchRequests{requests: [%GetTransactionInputs{}, %GetTransactionChain{}]}, _ ->
        {:ok,
         %BatchResponses{
           responses: [
             {0, %TransactionInputList{inputs: inputs}},
             {1, %TransactionList{transactions: []}}
           ]
         }}
    end)

    tx_summary = %TransactionSummary{address: "@Alice2"}
    assert :ok = TransactionHandler.download_transaction(tx_summary, "AAA")

    assert_received :transaction_replicated
  end
end
