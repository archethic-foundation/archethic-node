defmodule UnirisWeb.GraphQLSchemaTest do
  use UnirisCase
  use UnirisWeb.ConnCase
  use UnirisWeb.GraphQLSubscriptionCase

  alias Uniris.Account.MemTables.NFTLedger
  alias Uniris.Account.MemTables.UCOLedger

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Batcher
  alias Uniris.P2P.Message.BatchRequests
  alias Uniris.P2P.Message.BatchResponses
  alias Uniris.P2P.Message.GetLastTransaction
  alias Uniris.P2P.Message.NotFound
  alias Uniris.P2P.Node

  alias Uniris.PubSub

  alias Uniris.TransactionChain.MemTables.ChainLookup
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Uniris.TransactionChain.TransactionData

  import Mox

  setup do
    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.node_public_key(),
      last_public_key: Crypto.node_public_key(),
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true
    })

    start_supervised!(Batcher)

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
      addr = <<0::8, :crypto.strong_rand_bytes(32)::binary>> |> Base.encode16()

      conn =
        post(conn, "/api", %{
          "query" => "query { transaction(address: \"#{addr}\") { address } }"
        })

      assert %{"errors" => [%{"message" => "transaction_not_exists"}]} = json_response(conn, 200)
    end

    test "should the transaction with the requested fields", %{conn: conn} do
      addr = <<0::8, :crypto.strong_rand_bytes(32)::binary>> |> Base.encode16()

      MockDB
      |> stub(:get_transaction, fn _, _ ->
        {:ok,
         %Transaction{
           address: addr,
           timestamp: DateTime.utc_now(),
           type: :transfer,
           data: %TransactionData{}
         }}
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
      first_addr = <<0::8, :crypto.strong_rand_bytes(32)::binary>>
      second_addr = <<0::8, :crypto.strong_rand_bytes(32)::binary>>
      third_addr = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

      ChainLookup.register_last_address(first_addr, first_addr)
      ChainLookup.register_last_address(first_addr, second_addr)
      ChainLookup.register_last_address(first_addr, third_addr)

      MockDB
      |> stub(:get_transaction, fn ^third_addr, _ ->
        {:ok,
         %Transaction{
           address: third_addr,
           timestamp: DateTime.utc_now(),
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

      assert third_addr == Base.decode16!(address, case: :mixed)
    end

    test "should return an error when no last transaction on this chain", %{conn: conn} do
      addr = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

      MockClient
      |> stub(:send_message, fn _, %BatchRequests{requests: [%GetLastTransaction{}]}, _ ->
        {:ok, %BatchResponses{responses: [{0, %NotFound{}}]}}
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
        addr1 = <<0::8, :crypto.strong_rand_bytes(32)::binary>>
        addr2 = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

        [
          %Transaction{
            address: addr1,
            timestamp: DateTime.utc_now(),
            type: :transfer,
            data: %TransactionData{}
          },
          %Transaction{
            address: addr2,
            timestamp: DateTime.utc_now(),
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
          addr = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

          %Transaction{
            address: addr,
            timestamp: DateTime.utc_now(),
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
          addr = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

          %Transaction{
            address: addr,
            timestamp: DateTime.utc_now(),
            type: :transfer,
            data: %TransactionData{}
          }
        end)

      MockDB
      |> stub(:get_transaction_chain, fn _, _ -> transactions end)

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
          addr = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

          %Transaction{
            address: addr,
            timestamp: DateTime.utc_now(),
            type: :transfer,
            data: %TransactionData{}
          }
        end)

      MockDB
      |> stub(:get_transaction_chain, fn _, _ -> transactions end)

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
      addr = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

      UCOLedger.add_unspent_output(
        addr,
        %UnspentOutput{
          from: :crypto.strong_rand_bytes(32),
          amount: 0.202
        },
        DateTime.utc_now()
      )

      UCOLedger.add_unspent_output(
        addr,
        %UnspentOutput{
          from: :crypto.strong_rand_bytes(32),
          amount: 0.518
        },
        DateTime.utc_now()
      )

      UCOLedger.add_unspent_output(
        addr,
        %UnspentOutput{
          from: :crypto.strong_rand_bytes(32),
          amount: 1.46
        },
        DateTime.utc_now()
      )

      conn =
        post(conn, "/api", %{
          "query" => "query { balance(address: \"#{Base.encode16(addr)}\") { uco } }"
        })

      assert %{"data" => %{"balance" => %{"uco" => 2.18}}} = json_response(conn, 200)
    end

    test "should retrieve the nft balance of an address", %{conn: conn} do
      addr = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

      NFTLedger.add_unspent_output(
        addr,
        %UnspentOutput{
          from: :crypto.strong_rand_bytes(32),
          amount: 2.0,
          type: {:NFT, :crypto.strong_rand_bytes(32)}
        },
        DateTime.utc_now()
      )

      NFTLedger.add_unspent_output(
        addr,
        %UnspentOutput{
          from: :crypto.strong_rand_bytes(32),
          amount: 5.0,
          type: {:NFT, :crypto.strong_rand_bytes(32)}
        },
        DateTime.utc_now()
      )

      NFTLedger.add_unspent_output(
        addr,
        %UnspentOutput{
          from: :crypto.strong_rand_bytes(32),
          amount: 10.0,
          type: {:NFT, :crypto.strong_rand_bytes(32)}
        },
        DateTime.utc_now()
      )

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
      addr = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

      UCOLedger.add_unspent_output(
        addr,
        %UnspentOutput{
          from: :crypto.strong_rand_bytes(32),
          amount: 0.202
        },
        ~U[2021-03-05 13:41:34Z]
      )

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

  describe "subscription: acknowledge_storage" do
    test "should be notified when the welcome node get acknowledgment of the transaction stored" do
      addr = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

      socket = get_socket()

      subscription_id =
        subscribe(
          socket,
          "subscription { acknowledge_storage(address: \"#{Base.encode16(addr)}\") { address } }"
        )

      PubSub.notify_new_transaction(addr)

      MockDB
      |> expect(:get_transaction, fn _, _ ->
        {:ok, %Transaction{address: addr, type: :transfer, data: %TransactionData{}}}
      end)

      assert_push("subscription:data", push)

      assert %{
               result: %{data: %{"acknowledge_storage" => %{"address" => recv_addr}}},
               subscriptionId: ^subscription_id
             } = push

      assert recv_addr == Base.encode16(addr)
    end
  end
end
