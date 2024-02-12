defmodule Archethic.Replication.TransactionContextTest do
  use ArchethicCase
  import ArchethicCase

  alias Archethic.Account.MemTables.UCOLedger

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetTransactionChain
  alias Archethic.P2P.Message.GetTransactionInputs
  alias Archethic.P2P.Message.TransactionInputList
  alias Archethic.P2P.Message.TransactionList
  alias Archethic.P2P.Node

  alias Archethic.Replication.TransactionContext

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.VersionedTransactionInput

  import Mox

  test "fetch_transaction/1 should retrieve the transaction" do
    MockClient
    |> stub(:send_message, fn _, %GetTransaction{}, _ ->
      {:ok, %Transaction{}}
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

    assert %Transaction{} = TransactionContext.fetch_transaction("@Alice1")
  end

  test "stream_transaction_chain/1 should retrieve the previous transaction chain" do
    pub1 = random_public_key()
    pub2 = random_public_key()

    genesis = random_address()
    addr1 = Crypto.derive_address(pub1)
    addr2 = Crypto.derive_address(pub2)

    MockDB
    |> expect(:get_last_chain_address_stored, fn ^genesis -> addr1 end)

    MockClient
    |> expect(:send_message, fn
      _, %GetTransactionChain{address: ^genesis, paging_state: ^addr1}, _ ->
        {:ok,
         %TransactionList{
           transactions: [
             %Transaction{previous_public_key: pub1},
             %Transaction{previous_public_key: pub2}
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

    chain =
      genesis
      |> TransactionContext.stream_transaction_chain(addr2, P2P.authorized_and_available_nodes())
      |> Enum.to_list()

    assert [%Transaction{previous_public_key: ^pub1}] = chain
  end

  test "fetch_transaction_inputs/2 should retrieve the inputs of a transaction at a given date" do
    UCOLedger.add_unspent_output(
      "@Alice1",
      %VersionedUnspentOutput{
        unspent_output: %UnspentOutput{
          from: "@Bob3",
          amount: 19_300_000,
          type: :UCO,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
        },
        protocol_version: 1
      }
    )

    MockClient
    |> stub(:send_message, fn _, %GetTransactionInputs{}, _ ->
      {:ok,
       %TransactionInputList{
         inputs: [
           %VersionedTransactionInput{
             input: %TransactionInput{
               from: "@Bob3",
               amount: 19_300_000,
               type: :UCO,
               timestamp: DateTime.utc_now()
             },
             protocol_version: 1
           }
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
             TransactionContext.fetch_transaction_unspent_outputs("@Alice1", DateTime.utc_now())
  end
end
