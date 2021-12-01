defmodule ArchEthic.Replication.TransactionContextTest do
  use ArchEthicCase

  alias ArchEthic.Account.MemTables.UCOLedger

  alias ArchEthic.Crypto

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.GetTransactionChain
  alias ArchEthic.P2P.Message.GetUnspentOutputs
  alias ArchEthic.P2P.Message.TransactionList
  alias ArchEthic.P2P.Message.UnspentOutputList
  alias ArchEthic.P2P.Node

  alias ArchEthic.Replication.TransactionContext

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  import Mox

  test "fetch_transaction_chain/1 should retrieve the previous transaction chain" do
    MockClient
    |> stub(:send_message, fn _, %GetTransactionChain{}, _ ->
      {:ok, %TransactionList{transactions: [%Transaction{}]}}
    end)

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.last_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA",
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    assert 1 =
             TransactionContext.fetch_transaction_chain("@Alice1", DateTime.utc_now())
             |> Enum.count()
  end

  test "fetch_unspent_outputs/1 should retrieve the previous unspent outputs" do
    UCOLedger.add_unspent_output(
      "@Alice1",
      %UnspentOutput{
        from: "@Bob3",
        amount: 19_300_000,
        type: :UCO
      },
      ~U[2021-03-05 13:41:34Z]
    )

    MockClient
    |> stub(:send_message, fn _, %GetUnspentOutputs{}, _ ->
      {:ok,
       %UnspentOutputList{
         unspent_outputs: [
           %UnspentOutput{from: "@Bob3", amount: 19_300_000, type: :UCO}
         ]
       }}
    end)

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.last_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA",
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    assert [%UnspentOutput{from: "@Bob3", amount: 19_300_000, type: :UCO}] =
             TransactionContext.fetch_unspent_outputs("@Alice1", DateTime.utc_now())
             |> Enum.to_list()
  end

  test "fetch_transaction_inputs/2 should retrieve the inputs of a transaction at a given date" do
    UCOLedger.add_unspent_output(
      "@Alice1",
      %UnspentOutput{
        from: "@Bob3",
        amount: 19_300_000,
        type: :UCO
      },
      ~U[2021-03-05 13:41:34Z]
    )

    MockClient
    |> stub(:send_message, fn _, %GetUnspentOutputs{}, _ ->
      {:ok,
       %UnspentOutputList{
         unspent_outputs: [
           %UnspentOutput{from: "@Bob3", amount: 19_300_000, type: :UCO}
         ]
       }}
    end)

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.last_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA",
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    assert [%UnspentOutput{from: "@Bob3", amount: 19_300_000, type: :UCO}] =
             TransactionContext.fetch_unspent_outputs("@Alice1", DateTime.utc_now())
             |> Enum.to_list()
  end
end
