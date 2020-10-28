defmodule Uniris.Replication.TransactionContextTest do
  use UnirisCase

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetTransactionChain
  alias Uniris.P2P.Message.GetUnspentOutputs
  alias Uniris.P2P.Message.TransactionList
  alias Uniris.P2P.Message.UnspentOutputList
  alias Uniris.P2P.Node

  alias Uniris.Replication.TransactionContext

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  import Mox

  test "fetch_transaction_chain/1 should retrieve the previous transaction chain" do
    MockTransport
    |> stub(:send_message, fn _, _, %GetTransactionChain{} ->
      {:ok, %TransactionList{transactions: [%Transaction{}]}}
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
    MockTransport
    |> stub(:send_message, fn _, _, %GetUnspentOutputs{} ->
      {:ok, %UnspentOutputList{unspent_outputs: [%UnspentOutput{from: "@Bob3", amount: 0.193}]}}
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

    assert [%UnspentOutput{from: "@Bob3", amount: 0.193}] =
             TransactionContext.fetch_unspent_outputs("@Alice1") |> Enum.to_list()
  end
end
