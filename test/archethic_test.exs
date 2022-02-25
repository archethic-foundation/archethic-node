defmodule ArchEthicTest do
  use ArchEthicCase

  alias ArchEthic

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
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionInput

  import Mox

  describe "search_transaction/1" do
    test "should request storage nodes and return the transaction" do
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
      |> expect(:send_message, fn _, %GetTransaction{}, _ ->
        {:ok, %Transaction{address: "@Alice2"}}
      end)

      assert {:ok, %Transaction{address: "@Alice2"}} = ArchEthic.search_transaction("@Alice2")
    end

    test "should request storage nodes and return not exists as the transaction not exists" do
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
      |> expect(:send_message, fn _, %GetTransaction{}, _ ->
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

      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      MockClient
      |> expect(:send_message, fn _, %StartMining{}, _ ->
        Process.sleep(1_000)
        PubSub.notify_new_transaction(tx.address)
        {:ok, %Ok{}}
      end)

      assert :ok = ArchEthic.send_new_transaction(tx)
    end
  end

  describe "get_last_transaction/1" do
    test "should request storages nodes to fetch the last transaction" do
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
      |> expect(:send_message, fn _, %GetLastTransaction{}, _ ->
        {:ok, %Transaction{previous_public_key: "Alice1"}}
      end)

      assert {:ok, %Transaction{previous_public_key: "Alice1"}} =
               ArchEthic.get_last_transaction(Crypto.hash("Alice1"))
    end

    test "should request storages nodes to fetch the last transaction but not exists" do
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
      |> expect(:send_message, fn _, %GetLastTransaction{}, _ ->
        {:ok, %NotFound{}}
      end)

      assert {:error, :transaction_not_exists} =
               ArchEthic.get_last_transaction(Crypto.hash("Alice1"))
    end
  end

  describe "get_balance/1" do
    test "should request storage nodes to fetch the balance" do
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
      |> expect(:send_message, fn _, %GetBalance{}, _ ->
        {:ok, %Balance{uco: 1_000_000_000}}
      end)

      assert {:ok, %{uco: 1_000_000_000}} = ArchEthic.get_balance("@Alice2")
    end
  end

  describe "get_transaction_inputs/1" do
    test "should request the storages nodes to fetch the inputs remotely" do
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
      |> expect(:send_message, fn _, %GetTransactionInputs{}, _ ->
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

      assert {:ok,
              [%TransactionInput{from: "@Bob3", amount: 1_000_000_000, spent?: false, type: :UCO}]} =
               ArchEthic.get_transaction_inputs("@Alice2")
    end
  end

  describe "get_transaction_chain/1" do
    test "should request the storage node to fetch the transaction chain" do
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
      |> expect(:send_message, fn _, %GetTransactionChain{}, _ ->
        {:ok,
         %TransactionList{
           transactions: [
             %Transaction{address: "@Alice2"},
             %Transaction{address: "@Alice1"}
           ]
         }}
      end)

      assert {:ok, [%Transaction{address: "@Alice2"}, %Transaction{address: "@Alice1"}]} =
               ArchEthic.get_transaction_chain("@Alice2")
    end
  end

  describe "get_transaction_chain_length/1" do
    test "should request the storage node to fetch the transaction chain length" do
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
      |> expect(:send_message, fn _, %GetTransactionChainLength{}, _ ->
        {:ok, %TransactionChainLength{length: 3}}
      end)

      assert {:ok, 3} == ArchEthic.get_transaction_chain_length("@Alice2")
    end
  end

  describe "Testing the NodeMetricEndpoint Service" do
    test "&establish_connection(&1 <- ip_as_string)" do
      MockMetrics
      |> expect(:establish_connection, fn ip_as_string ->
        %Mint.HTTP1{
          buffer: "",
          host: ip_as_string,
          mode: :active,
          port: 40000,
          private: %{},
          proxy_headers: [],
          request: nil,
          requests: {[], []},
          scheme_as_string: "http",
          socket: "identifer",
          state: :open,
          streaming_request: nil,
          transport: Mint.Core.Transport.TCP
        }
      end)

      MockMetrics
      |> expect(:contact_endpoint, fn _connection_ref ->
        [
          {:status, "reference()", 200},
          {:headers, "reference()",
           [
             {"access-control-allow-credentials", "true"},
             {"access-control-allow-origin", "*"},
             {"access-control-expose-headers", ""},
             {"cache-control", "max-age=0, private, must-revalidate"},
             {"content-length", "21451"},
             {"content-type", "text/plain; charset=utf-8"},
             {"cross-origin-window-policy", "deny"},
             {"date", "Fri, 25 Feb 2022 10:40:06 GMT"},
             {"server", "Cowboy"},
             {"x-content-type-options", "nosniff"},
             {"x-download-options", "noopen"},
             {"x-frame-options", "SAMEORIGIN"},
             {"x-permitted-cross-domain-policies", "none"},
             {"x-request-id", "FtcBSlRL9jlMYh8AAADC"},
             {"x-xss-protection", "1; mode=block"}
           ]},
          {:data, "reference()", "#metrics"},
          {:done, "reference()"}
        ]
      end)

      conn_ref = MockMetrics.establish_connection("172.16.1.10")

      assert Mint.HTTP1 == conn_ref.__struct__
      assert conn_ref.host == "172.16.1.10"

      response = MockMetrics.contact_endpoint(conn_ref)

      assert [{:status, "reference()", 200}] ==
               Enum.filter(response, fn x ->
                 case x do
                   {:status, _, _} -> true
                   _ -> false
                 end
               end)
    end
  end
end
