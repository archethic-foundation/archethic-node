defmodule ArchEthicTest do
  use ArchEthicCase

  alias ArchEthic

  alias ArchEthic.Account.MemTables.UCOLedger

  alias ArchEthic.Crypto

  alias ArchEthic.PubSub

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.Balance
  alias ArchEthic.P2P.Message.GetBalance
  alias ArchEthic.P2P.Message.GetLastTransaction
  alias ArchEthic.P2P.Message.GetTransaction
  alias ArchEthic.P2P.Message.GetTransactionChain
  alias ArchEthic.P2P.Message.GetTransactionChainLength
  alias ArchEthic.P2P.Message.GetTransactionInputs
  alias ArchEthic.P2P.Message.NotFound
  alias ArchEthic.P2P.Message.Ok
  alias ArchEthic.P2P.Message.StartMining
  alias ArchEthic.P2P.Message.TransactionChainLength
  alias ArchEthic.P2P.Message.TransactionInputList
  alias ArchEthic.P2P.Message.TransactionList
  alias ArchEthic.P2P.Node

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionInput

  import Mox

  describe "search_transaction/1" do
    test "should fetch the transaction locally when the current node is a storage node" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.last_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      MockDB
      |> expect(:get_transaction, fn _, _ ->
        {:ok, %Transaction{address: "@Alice2"}}
      end)

      assert {:ok, %Transaction{address: "@Alice2"}} = ArchEthic.search_transaction("@Alice2")
    end

    test "should fetch the transaction locally if the current node is not a storage node and return not exists as the transaction not exists" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.last_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      MockDB
      |> expect(:get_transaction, fn _, _ ->
        {:error, :transaction_not_exists}
      end)

      assert {:error, :transaction_not_exists} = ArchEthic.search_transaction("@Alice2")
    end

    test "should request storage nodes if the current node is not a storage node and return the transaction" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.last_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA"
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      MockClient
      |> expect(:send_message, fn _, %GetTransaction{} ->
        {:ok, %Transaction{address: "@Alice2"}}
      end)

      assert {:ok, %Transaction{address: "@Alice2"}} = ArchEthic.search_transaction("@Alice2")
    end

    test "should request storage nodes if the current node is not a storage node and return not exists as the transaction not exists" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.last_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA"
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      MockClient
      |> expect(:send_message, fn _, %GetTransaction{} ->
        {:ok, %NotFound{}}
      end)

      assert {:error, :transaction_not_exists} = ArchEthic.search_transaction("@Alice2")
    end
  end

  describe "send_new_transaction/1" do
    test "should elect validation nodes and broadcast the transaction" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-1)
      })

      me = self()

      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      MockClient
      |> expect(:send_message, fn _, %StartMining{} ->
        send(me, :ack_mining)
        PubSub.notify_new_transaction(tx.address)
        {:ok, %Ok{}}
      end)

      assert :ok = ArchEthic.send_new_transaction(tx)

      assert_receive :ack_mining
    end
  end

  describe "get_last_transaction/1" do
    test "should fetch the transaction locally when the current node is a storage node" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.last_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      MockDB
      |> expect(:get_last_chain_address, fn _ -> Crypto.hash("Alice2") end)
      |> expect(:get_transaction, fn address, _ ->
        if address == Crypto.hash("Alice2") do
          {:ok, %Transaction{previous_public_key: "Alice1"}}
        end
      end)

      assert {:ok, %Transaction{previous_public_key: "Alice1"}} =
               ArchEthic.get_last_transaction(Crypto.hash("Alice1"))
    end

    test "should fetch the transaction remotely when the current node does not have reference from the last one" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.last_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: :crypto.strong_rand_bytes(32),
        last_public_key: :crypto.strong_rand_bytes(32),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      MockClient
      |> expect(:send_message, fn _, %GetLastTransaction{} ->
        {:ok, %Transaction{previous_public_key: "Alice1"}}
      end)

      MockDB
      |> expect(:get_last_chain_address, fn addr -> addr end)

      assert {:ok, %Transaction{previous_public_key: "Alice1"}} =
               ArchEthic.get_last_transaction(Crypto.hash("Alice1"))
    end

    test "should fetch the transaction remotely when the current node does not have reference from the last one but not exists" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.last_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: :crypto.strong_rand_bytes(32),
        last_public_key: :crypto.strong_rand_bytes(32),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      MockClient
      |> expect(:send_message, fn _, %GetLastTransaction{} ->
        {:ok, %NotFound{}}
      end)

      MockDB
      |> expect(:get_last_chain_address, fn addr -> addr end)

      assert {:error, :transaction_not_exists} =
               ArchEthic.get_last_transaction(Crypto.hash("Alice1"))
    end
  end

  describe "get_balance/1" do
    test "should fetch the address balance when the current node is a storage node" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.last_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      :ok =
        UCOLedger.add_unspent_output(
          "@Alice2",
          %UnspentOutput{from: "@Bob3", amount: 1_000_000_000},
          DateTime.utc_now()
        )

      assert %{uco: 1_000_000_000} = ArchEthic.get_balance("@Alice2")
    end

    test "should request storage nodes if the current node is not a storage node and return the balance" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.last_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA"
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      MockClient
      |> expect(:send_message, fn _, %GetBalance{} ->
        {:ok, %Balance{uco: 1_000_000_000}}
      end)

      assert %{uco: 1_000_000_000} = ArchEthic.get_balance("@Alice2")
    end
  end

  describe "get_transaction_inputs/1" do
    test "should fetch the inputs locally when the current node is a storage node" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.last_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      :ok =
        UCOLedger.add_unspent_output(
          "@Alice2",
          %UnspentOutput{
            from: "@Bob3",
            amount: 1_000_000_000,
            type: :UCO
          },
          DateTime.utc_now()
        )

      assert [%TransactionInput{from: "@Bob3", amount: 1_000_000_000, spent?: false, type: :UCO}] =
               ArchEthic.get_transaction_inputs("@Alice2")
    end

    test "should fetch the inputs remotely when the current node is not a storage node" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.last_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA"
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      MockClient
      |> expect(:send_message, fn _, %GetTransactionInputs{} ->
        {:ok,
         %TransactionInputList{
           inputs: [
             %TransactionInput{
               from: "@Bob3",
               amount: 1_000_000_000,
               spent?: false,
               type: :UCO,
               timestamp: DateTime.utc_now()
             }
           ]
         }}
      end)

      assert [%TransactionInput{from: "@Bob3", amount: 1_000_000_000, spent?: false, type: :UCO}] =
               ArchEthic.get_transaction_inputs("@Alice2")
    end
  end

  describe "get_transaction_chain/1" do
    test "should fetch the transaction chain locally when the current node is a storage node" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.last_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      MockDB
      |> expect(:get_transaction_chain, fn _, _ ->
        [%Transaction{address: "@Alice2"}, %Transaction{address: "@Alice1"}]
      end)

      assert [%Transaction{address: "@Alice2"}, %Transaction{address: "@Alice1"}] =
               ArchEthic.get_transaction_chain("@Alice2")
    end

    test "should fetch the transaction chain remotely when the current node is not a storage node" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.last_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA"
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      MockClient
      |> expect(:send_message, fn _, %GetTransactionChain{} ->
        {:ok,
         %TransactionList{
           transactions: [%Transaction{address: "@Alice2"}, %Transaction{address: "@Alice1"}]
         }}
      end)

      assert [%Transaction{address: "@Alice2"}, %Transaction{address: "@Alice1"}] =
               ArchEthic.get_transaction_chain("@Alice2")
    end
  end

  describe "get_transaction_chain_length/1" do
    test "should fetch the transaction chain locally when the current node is a storage node" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.last_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      MockDB
      |> stub(:chain_size, fn address ->
        cond do
          address == Crypto.hash("Alice1") ->
            1

          address == Crypto.hash("Alice2") ->
            2

          true ->
            0
        end
      end)

      assert 1 == ArchEthic.get_transaction_chain_length(Crypto.hash("Alice1"))
      assert 2 == ArchEthic.get_transaction_chain_length(Crypto.hash("Alice2"))
    end

    test "should fetch the transaction chain remotely when the current node is not a storage node" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.last_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA"
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key1",
        last_public_key: "key1",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      MockClient
      |> expect(:send_message, fn _, %GetTransactionChainLength{} ->
        {:ok,
         %TransactionChainLength{
           length: 3
         }}
      end)

      assert 3 == ArchEthic.get_transaction_chain_length("@Alice2")
    end
  end
end
