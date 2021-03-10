defmodule Uniris.Replication.TransactionContextTest do
  use UnirisCase

  alias Uniris.Account.MemTables.UCOLedger

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Batcher
  alias Uniris.P2P.Message.BatchRequests
  alias Uniris.P2P.Message.BatchResponses
  alias Uniris.P2P.Message.GetTransactionChain
  alias Uniris.P2P.Message.GetUnspentOutputs
  alias Uniris.P2P.Message.TransactionList
  alias Uniris.P2P.Message.UnspentOutputList
  alias Uniris.P2P.Node

  alias Uniris.Replication.TransactionContext

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  import Mox

  setup do
    start_supervised!(Batcher)
    :ok
  end

  test "fetch_transaction_chain/1 should retrieve the previous transaction chain" do
    MockClient
    |> stub(:send_message, fn _, %BatchRequests{requests: [%GetTransactionChain{}]}, _ ->
      {:ok, %BatchResponses{responses: [{0, %TransactionList{transactions: [%Transaction{}]}}]}}
    end)

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.node_public_key(),
      last_public_key: Crypto.node_public_key(),
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA"
    })

    assert 1 = TransactionContext.fetch_transaction_chain("@Alice1") |> Enum.count()
  end

  test "fetch_unspent_outputs/1 should retrieve the previous unspent outputs" do
    UCOLedger.add_unspent_output(
      "@Alice1",
      %UnspentOutput{
        from: "@Bob3",
        amount: 0.193,
        type: :UCO
      },
      ~U[2021-03-05 13:41:34Z]
    )

    MockClient
    |> stub(:send_message, fn _, %BatchRequests{requests: [%GetUnspentOutputs{}]}, _ ->
      {:ok,
       %BatchResponses{
         responses: [
           {0,
            %UnspentOutputList{
              unspent_outputs: [%UnspentOutput{from: "@Bob3", amount: 0.193, type: :UCO}]
            }}
         ]
       }}
    end)

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.node_public_key(),
      last_public_key: Crypto.node_public_key(),
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA"
    })

    assert [%UnspentOutput{from: "@Bob3", amount: 0.193, type: :UCO}] =
             TransactionContext.fetch_unspent_outputs("@Alice1") |> Enum.to_list()
  end

  test "fetch_transaction_inputs/2 should retrieve the inputs of a transaction at a given date" do
    UCOLedger.add_unspent_output(
      "@Alice1",
      %UnspentOutput{
        from: "@Bob3",
        amount: 0.193,
        type: :UCO
      },
      ~U[2021-03-05 13:41:34Z]
    )

    MockClient
    |> stub(:send_message, fn _, %BatchRequests{requests: [%GetUnspentOutputs{}]}, _ ->
      {:ok,
       %BatchResponses{
         responses: [
           {0,
            %UnspentOutputList{
              unspent_outputs: [%UnspentOutput{from: "@Bob3", amount: 0.193, type: :UCO}]
            }}
         ]
       }}
    end)

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.node_public_key(),
      last_public_key: Crypto.node_public_key(),
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA"
    })

    assert [%UnspentOutput{from: "@Bob3", amount: 0.193, type: :UCO}] =
             TransactionContext.fetch_unspent_outputs("@Alice1") |> Enum.to_list()
  end
end
