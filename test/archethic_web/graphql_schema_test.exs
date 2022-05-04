defmodule ArchethicWeb.GraphQLSchemaTest do
  use ArchethicCase
  use ArchethicWeb.ConnCase
  use ArchethicWeb.GraphQLSubscriptionCase

  alias Archethic.Crypto

  alias Archethic.BeaconChain.ReplicationAttestation

  alias Archethic.P2P
  alias Archethic.P2P.Message.Balance
  alias Archethic.P2P.Message.GetBalance
  alias Archethic.P2P.Message.GetLastTransaction
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetTransactionChain
  alias Archethic.P2P.Message.GetTransactionInputs
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Message.TransactionInputList
  alias Archethic.P2P.Message.TransactionList
  alias Archethic.P2P.Node

  alias Archethic.PubSub

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.TransactionSummary

  import Mox

  setup do
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

    :ok
  end

  describe "query: transaction" do
    test "should return an error when the given address is invalid", %{conn: conn} do
      addr = :crypto.strong_rand_bytes(32) |> Base.encode16()

      conn =
        post(conn, "/api", %{
          "query" => "query { transaction(address: \"#{addr}\") { address } }"
        })

      %{"errors" => [%{"message" => message}]} = json_response(conn, 200)
      assert String.contains?(message, "Argument \"address\" has invalid value")
    end

    test "should return nothing when the transaction is not found", %{conn: conn} do
      addr = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>> |> Base.encode16()

      MockClient
      |> stub(:send_message, fn _, %GetTransaction{}, _ ->
        {:ok, %NotFound{}}
      end)

      conn =
        post(conn, "/api", %{
          "query" => "query { transaction(address: \"#{addr}\") { address } }"
        })

      assert %{"errors" => [%{"message" => "transaction_not_exists"}]} = json_response(conn, 200)
    end

    test "should the transaction with the requested fields", %{conn: conn} do
      addr = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>> |> Base.encode16()

      MockClient
      |> stub(:send_message, fn _, %GetTransaction{}, _ ->
        {:ok, %Transaction{address: addr, type: :transfer, data: %TransactionData{}}}
      end)

      conn =
        post(conn, "/api", %{
          "query" => "query { transaction(address: \"#{addr}\") { address } }"
        })

      assert %{"data" => %{"transaction" => %{"address" => address}}} = json_response(conn, 200)
      assert addr == Base.decode16!(address, case: :mixed)
    end
  end

  describe "query: last_transaction" do
    test "should retrieve the last transaction of a chain", %{conn: conn} do
      first_addr = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      last_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      MockClient
      |> stub(:send_message, fn _, %GetLastTransaction{}, _ ->
        {:ok,
         %Transaction{
           address: last_address,
           type: :transfer,
           data: %TransactionData{}
         }}
      end)

      conn =
        post(conn, "/api", %{
          "query" =>
            "query { last_transaction(address: \"#{Base.encode16(first_addr)}\") { address } }"
        })

      assert %{"data" => %{"last_transaction" => %{"address" => address}}} =
               json_response(conn, 200)

      assert last_address == Base.decode16!(address, case: :mixed)
    end

    test "should return an error when no last transaction on this chain", %{conn: conn} do
      addr = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      MockClient
      |> stub(:send_message, fn _, %GetLastTransaction{}, _ ->
        {:ok, %NotFound{}}
      end)

      conn =
        post(conn, "/api", %{
          "query" => "query { last_transaction(address: \"#{Base.encode16(addr)}\") { address } }"
        })

      assert %{"errors" => [%{"message" => "transaction_not_exists"}]} = json_response(conn, 200)
    end
  end

  describe "query: transactions" do
    test "should retrieve the first page of transaction stored locally", %{conn: conn} do
      MockDB
      |> stub(:list_transactions, fn _ ->
        addr1 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
        addr2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

        [
          %Transaction{
            address: addr1,
            type: :transfer,
            data: %TransactionData{}
          },
          %Transaction{
            address: addr2,
            type: :transfer,
            data: %TransactionData{}
          }
        ]
      end)

      conn =
        post(conn, "/api", %{
          "query" => "query { transactions { address } }"
        })

      assert %{"data" => %{"transactions" => transactions}} = json_response(conn, 200)
      assert Enum.count(transactions) == 2
    end

    test "should retrieve the second page of transaction stored locally", %{conn: conn} do
      MockDB
      |> stub(:list_transactions, fn _ ->
        Enum.map(1..20, fn _ ->
          addr = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

          %Transaction{
            address: addr,
            type: :transfer,
            data: %TransactionData{}
          }
        end)
      end)

      conn =
        post(conn, "/api", %{
          "query" => "query { transactions(page: 2) { address } }"
        })

      assert %{"data" => %{"transactions" => transactions}} = json_response(conn, 200)
      assert Enum.count(transactions) == 10
    end
  end

  describe "query: transaction_chain" do
    test "should retrieve the first page of a transaction chain", %{conn: conn} do
      transactions =
        Enum.map(1..20, fn _ ->
          addr = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

          %Transaction{
            address: addr,
            type: :transfer,
            data: %TransactionData{}
          }
        end)

      MockClient
      |> stub(:send_message, fn _, %GetTransactionChain{}, _ ->
        {:ok,
         %TransactionList{
           transactions: transactions
         }}
      end)

      last_addr = List.last(transactions).address

      conn =
        post(conn, "/api", %{
          "query" =>
            "query { transactionChain(address: \"#{Base.encode16(last_addr)}\") { address } }"
        })

      assert %{"data" => %{"transactionChain" => transactions}} = json_response(conn, 200)
      assert Enum.count(transactions) == 10
    end

    test "should retrieve the second page of transaction chain", %{conn: conn} do
      transactions =
        Enum.map(1..20, fn _ ->
          addr = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

          %Transaction{
            address: addr,
            type: :transfer,
            data: %TransactionData{}
          }
        end)

      MockClient
      |> stub(:send_message, fn _, %GetTransactionChain{}, _ ->
        {:ok, %TransactionList{transactions: transactions}}
      end)

      last_addr = List.last(transactions).address

      conn =
        post(conn, "/api", %{
          "query" =>
            "query { transactionChain(address: \"#{Base.encode16(last_addr)}\", page: 2) { address } }"
        })

      assert %{"data" => %{"transactionChain" => recv_transactions}} = json_response(conn, 200)
      assert Enum.count(recv_transactions) == 10

      assert Enum.slice(transactions, 10..20)
             |> Enum.map(&%{"address" => Base.encode16(&1.address)}) == recv_transactions
    end
  end

  describe "query: balance" do
    test "should retrieve the uco balance of an address", %{conn: conn} do
      addr = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      MockClient
      |> stub(:send_message, fn _, %GetBalance{}, _ ->
        {:ok, %Balance{uco: 218_000_000}}
      end)

      conn =
        post(conn, "/api", %{
          "query" => "query { balance(address: \"#{Base.encode16(addr)}\") { uco } }"
        })

      assert %{"data" => %{"balance" => %{"uco" => 2.18}}} = json_response(conn, 200)
    end

    test "should retrieve the nft balance of an address", %{conn: conn} do
      addr = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      MockClient
      |> stub(:send_message, fn _, %GetBalance{}, _ ->
        {:ok,
         %Balance{
           nft: %{
             "@NFT1" => 200_000_000,
             "@NFT2" => 500_000_000,
             "@NFT3" => 1_000_000_000
           }
         }}
      end)

      conn =
        post(conn, "/api", %{
          "query" => "query { balance(address: \"#{Base.encode16(addr)}\") { nft { amount } } }"
        })

      assert %{
               "data" => %{
                 "balance" => %{
                   "nft" => [%{"amount" => 2.0}, %{"amount" => 5.0}, %{"amount" => 10.0}]
                 }
               }
             } = json_response(conn, 200)
    end
  end

  describe "query: transaction_inputs" do
    test "should return a list of ledger inputs", %{conn: conn} do
      addr = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      MockClient
      |> stub(:send_message, fn _, %GetTransactionInputs{}, _ ->
        {:ok,
         %TransactionInputList{
           inputs: [
             %TransactionInput{
               from: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
               amount: 20_200_000,
               type: :UCO,
               timestamp: DateTime.from_unix!(1_614_951_694)
             }
           ]
         }}
      end)

      conn =
        post(conn, "/api", %{
          "query" =>
            "query { transaction_inputs(address: \"#{Base.encode16(addr)}\") { type, amount, timestamp } }"
        })

      assert %{
               "data" => %{
                 "transaction_inputs" => [
                   %{
                     "type" => "UCO",
                     "amount" => 0.202,
                     "timestamp" => 1_614_951_694
                   }
                 ]
               }
             } = json_response(conn, 200)
    end
  end

  describe "query: shared_secrets" do
    test "should return the storage nonce's public key", %{conn: conn} do
      conn =
        post(conn, "/api", %{
          "query" => "query { shared_secrets { storage_nonce_public_key } }"
        })

      assert %{
               "data" => %{"shared_secrets" => %{"storage_nonce_public_key" => storage_nonce}}
             } = json_response(conn, 200)

      assert storage_nonce == Crypto.storage_nonce_public_key() |> Base.encode16()
    end
  end

  describe "subscription: transaction_confirmed" do
    test "should be notified when the welcome node get acknowledgment of the transaction stored" do
      addr = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      socket = get_socket()

      subscription_id =
        subscribe(
          socket,
          "subscription { transactionConfirmed(address: \"#{Base.encode16(addr)}\") { address, nbConfirmations } }"
        )

      PubSub.notify_replication_attestation(%ReplicationAttestation{
        transaction_summary: %TransactionSummary{
          address: addr,
          type: :transfer
        },
        confirmations: [{0, :crypto.strong_rand_bytes(64)}]
      })

      assert_push("subscription:data", push)

      assert %{
               result: %{
                 data: %{
                   "transactionConfirmed" => %{"address" => recv_addr, "nbConfirmations" => 1}
                 }
               },
               subscriptionId: ^subscription_id
             } = push

      assert recv_addr == Base.encode16(addr)
    end
  end
end
