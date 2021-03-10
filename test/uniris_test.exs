defmodule UnirisTest do
  use UnirisCase

  alias Uniris

  alias Uniris.Account.MemTables.UCOLedger

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Batcher
  alias Uniris.P2P.Message.Balance
  alias Uniris.P2P.Message.BatchRequests
  alias Uniris.P2P.Message.BatchResponses
  alias Uniris.P2P.Message.GetBalance
  alias Uniris.P2P.Message.GetLastTransaction
  alias Uniris.P2P.Message.GetTransaction
  alias Uniris.P2P.Message.GetTransactionChain
  alias Uniris.P2P.Message.GetTransactionChainLength
  alias Uniris.P2P.Message.GetTransactionInputs
  alias Uniris.P2P.Message.NotFound
  alias Uniris.P2P.Message.Ok
  alias Uniris.P2P.Message.StartMining
  alias Uniris.P2P.Message.TransactionChainLength
  alias Uniris.P2P.Message.TransactionInputList
  alias Uniris.P2P.Message.TransactionList
  alias Uniris.P2P.Node

  alias Uniris.TransactionChain.MemTables.ChainLookup
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionInput

  import Mox

  setup do
    start_supervised!(Batcher)
    :ok
  end

  describe "search_transaction/1" do
    test "should fetch the transaction locally when the current node is a storage node" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true
      })

      MockDB
      |> expect(:get_transaction, fn _, _ ->
        {:ok, %Transaction{address: "@Alice2"}}
      end)

      assert {:ok, %Transaction{address: "@Alice2"}} = Uniris.search_transaction("@Alice2")
    end

    test "should fetch the transaction locally if the current node is not a storage node and return not exists as the transaction not exists" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true
      })

      MockDB
      |> expect(:get_transaction, fn _, _ ->
        {:error, :transaction_not_exists}
      end)

      assert {:error, :transaction_not_exists} = Uniris.search_transaction("@Alice2")
    end

    test "should request storage nodes if the current node is not a storage node and return the transaction" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA"
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true
      })

      MockClient
      |> expect(:send_message, fn _, %BatchRequests{requests: [%GetTransaction{}]}, _ ->
        {:ok, %BatchResponses{responses: [{0, %Transaction{address: "@Alice2"}}]}}
      end)

      assert {:ok, %Transaction{address: "@Alice2"}} = Uniris.search_transaction("@Alice2")
    end

    test "should request storage nodes if the current node is not a storage node and return not exists as the transaction not exists" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA"
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true
      })

      MockClient
      |> expect(:send_message, fn _, %BatchRequests{requests: [%GetTransaction{}]}, _ ->
        {:ok, %BatchResponses{responses: [{0, %NotFound{}}]}}
      end)

      assert {:error, :transaction_not_exists} = Uniris.search_transaction("@Alice2")
    end
  end

  describe "send_new_transaction/1" do
    test "should elect validation nodes and broadcast the transaction" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(1),
        last_public_key: Crypto.node_public_key(1),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      me = self()

      MockClient
      |> expect(:send_message, fn _, %BatchRequests{requests: [%StartMining{}]}, _ ->
        send(me, :ack_mining)
        {:ok, %BatchResponses{responses: [{0, %Ok{}}]}}
      end)

      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)
      assert :ok = Uniris.send_new_transaction(tx)

      assert_receive :ack_mining
    end
  end

  describe "get_last_transaction/1" do
    test "should fetch the transaction locally when the current node is a storage node" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true
      })

      ChainLookup.reverse_link(Crypto.hash("Alice2"), "Alice1")
      ChainLookup.reverse_link(Crypto.hash("Alice1"), "Alice0")
      ChainLookup.get_last_chain_address(Crypto.hash("Alice1"))

      MockDB
      |> expect(:get_transaction, fn address, _ ->
        if address == Crypto.hash("Alice2") do
          {:ok, %Transaction{previous_public_key: "Alice1"}}
        end
      end)

      assert {:ok, %Transaction{previous_public_key: "Alice1"}} =
               Uniris.get_last_transaction(Crypto.hash("Alice1"))
    end

    test "should fetch the transaction remotely when the current node does not have reference from the last one" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA"
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: :crypto.strong_rand_bytes(32),
        last_public_key: :crypto.strong_rand_bytes(32),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true
      })

      MockClient
      |> expect(:send_message, fn _, %BatchRequests{requests: [%GetLastTransaction{}]}, _ ->
        {:ok, %BatchResponses{responses: [{0, %Transaction{previous_public_key: "Alice1"}}]}}
      end)

      assert {:ok, %Transaction{previous_public_key: "Alice1"}} =
               Uniris.get_last_transaction(Crypto.hash("Alice1"))
    end

    test "should fetch the transaction remotely when the current node does not have reference from the last one but not exists" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA"
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: :crypto.strong_rand_bytes(32),
        last_public_key: :crypto.strong_rand_bytes(32),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true
      })

      MockClient
      |> expect(:send_message, fn _, %BatchRequests{requests: [%GetLastTransaction{}]}, _ ->
        {:ok, %BatchResponses{responses: [{0, %NotFound{}}]}}
      end)

      assert {:error, :transaction_not_exists} =
               Uniris.get_last_transaction(Crypto.hash("Alice1"))
    end
  end

  describe "get_balance/1" do
    test "should fetch the address balance when the current node is a storage node" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true
      })

      :ok =
        UCOLedger.add_unspent_output(
          "@Alice2",
          %UnspentOutput{from: "@Bob3", amount: 10.0},
          DateTime.utc_now()
        )

      assert %{uco: 10.0} = Uniris.get_balance("@Alice2")
    end

    test "should request storage nodes if the current node is not a storage node and return the balance" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA"
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true
      })

      MockClient
      |> expect(:send_message, fn _, %BatchRequests{requests: [%GetBalance{}]}, _ ->
        {:ok, %BatchResponses{responses: [{0, %Balance{uco: 10.0}}]}}
      end)

      assert %{uco: 10.0} = Uniris.get_balance("@Alice2")
    end
  end

  describe "get_transaction_inputs/1" do
    test "should fetch the inputs locally when the current node is a storage node" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true
      })

      :ok =
        UCOLedger.add_unspent_output(
          "@Alice2",
          %UnspentOutput{
            from: "@Bob3",
            amount: 10.0,
            type: :UCO
          },
          DateTime.utc_now()
        )

      assert [%TransactionInput{from: "@Bob3", amount: 10.0, spent?: false, type: :UCO}] =
               Uniris.get_transaction_inputs("@Alice2")
    end

    test "should fetch the inputs remotely when the current node is not a storage node" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA"
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true
      })

      MockClient
      |> expect(:send_message, fn _, %BatchRequests{requests: [%GetTransactionInputs{}]}, _ ->
        {:ok,
         %BatchResponses{
           responses: [
             {0,
              %TransactionInputList{
                inputs: [
                  %TransactionInput{
                    from: "@Bob3",
                    amount: 10.0,
                    spent?: false,
                    type: :UCO,
                    timestamp: DateTime.utc_now()
                  }
                ]
              }}
           ]
         }}
      end)

      assert [%TransactionInput{from: "@Bob3", amount: 10.0, spent?: false, type: :UCO}] =
               Uniris.get_transaction_inputs("@Alice2")
    end
  end

  describe "get_transaction_chain/1" do
    test "should fetch the transaction chain locally when the current node is a storage node" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true
      })

      MockDB
      |> expect(:get_transaction_chain, fn _, _ ->
        [%Transaction{address: "@Alice2"}, %Transaction{address: "@Alice1"}]
      end)

      assert [%Transaction{address: "@Alice2"}, %Transaction{address: "@Alice1"}] =
               Uniris.get_transaction_chain("@Alice2")
    end

    test "should fetch the transaction chain remotely when the current node is not a storage node" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA"
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true
      })

      MockClient
      |> expect(:send_message, fn _, %BatchRequests{requests: [%GetTransactionChain{}]}, _ ->
        {:ok,
         %BatchResponses{
           responses: [
             {0,
              %TransactionList{
                transactions: [%Transaction{address: "@Alice2"}, %Transaction{address: "@Alice1"}]
              }}
           ]
         }}
      end)

      assert [%Transaction{address: "@Alice2"}, %Transaction{address: "@Alice1"}] =
               Uniris.get_transaction_chain("@Alice2")
    end
  end

  describe "get_transaction_chain_length/1" do
    test "should fetch the transaction chain locally when the current node is a storage node" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true
      })

      ChainLookup.reverse_link(Crypto.hash("Alice3"), "Alice2")
      ChainLookup.reverse_link(Crypto.hash("Alice2"), "Alice1")
      ChainLookup.reverse_link(Crypto.hash("Alice1"), "Alice0")

      assert 1 == Uniris.get_transaction_chain_length(Crypto.hash("Alice1"))
      assert 2 == Uniris.get_transaction_chain_length(Crypto.hash("Alice2"))
    end

    test "should fetch the transaction chain remotely when the current node is not a storage node" do
      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA"
      })

      P2P.add_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true
      })

      MockClient
      |> expect(:send_message, fn _,
                                  %BatchRequests{requests: [%GetTransactionChainLength{}]},
                                  _ ->
        {:ok,
         %BatchResponses{
           responses: [
             {0,
              %TransactionChainLength{
                length: 3
              }}
           ]
         }}
      end)

      assert 3 == Uniris.get_transaction_chain_length("@Alice2")
    end
  end
end
