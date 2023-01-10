defmodule ArchethicWeb.GraphQLSchemaTest do
  @moduledoc false
  use ArchethicCase
  use ArchethicWeb.ConnCase
  use ArchethicWeb.GraphQLSubscriptionCase

  alias Archethic.Crypto

  alias Archethic.BeaconChain.ReplicationAttestation

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetTransactionChainLength
  alias Archethic.P2P.Message.TransactionChainLength
  alias Archethic.P2P.Message.Balance
  alias Archethic.P2P.Message.FirstAddress
  alias Archethic.P2P.Message.GetBalance
  alias Archethic.P2P.Message.GetLastTransactionAddress
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetTransactionChain
  alias Archethic.P2P.Message.GetTransactionInputs
  alias Archethic.P2P.Message.LastTransactionAddress
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Message.TransactionInputList
  alias Archethic.P2P.Message.TransactionList
  alias Archethic.P2P.Message.GetFirstAddress
  alias Archethic.P2P.Node

  alias Archethic.PubSub

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.TransactionChain.TransactionSummary

  alias Archethic.Mining

  import Mox
  @transaction_chain_page_size 10

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
      authorization_date: DateTime.utc_now(),
      origin_public_key: <<0::0, 0::8, :crypto.strong_rand_bytes(32)::binary>>
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
      |> stub(:send_message, fn
        _, %GetLastTransactionAddress{}, _ ->
          {:ok, %LastTransactionAddress{address: last_address}}

        _, %GetTransaction{address: ^last_address}, _ ->
          {:ok, %Transaction{address: last_address, type: :transfer}}
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
      |> stub(:send_message, fn
        _, %GetLastTransactionAddress{address: address}, _ ->
          {:ok, %LastTransactionAddress{address: address}}

        _, %GetTransaction{}, _ ->
          {:ok, %NotFound{}}
      end)

      conn =
        post(conn, "/api", %{
          "query" => "query { last_transaction(address: \"#{Base.encode16(addr)}\") { address } }"
        })

      assert %{"errors" => [%{"message" => "transaction_not_exists"}]} = json_response(conn, 200)
    end
  end

  describe "query: token" do
    test "should return the ownerships", %{conn: conn} do
      token_addr = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      MockClient
      |> stub(:send_message, fn
        _, %GetFirstAddress{}, _ ->
          {:ok, %FirstAddress{address: token_addr}}

        _, %GetTransaction{}, _ ->
          aes_key = :crypto.strong_rand_bytes(32)
          transaction_seed = :crypto.strong_rand_bytes(32)
          storage_nonce_public_key = Crypto.storage_nonce_public_key()
          secret = Crypto.aes_encrypt(transaction_seed, aes_key)

          {:ok,
           %Transaction{
             type: :token,
             address: token_addr,
             data: %TransactionData{
               content: "{\"supply\": 1000000000, \"type\": \"fungible\" }",
               ownerships: [
                 %Ownership{
                   secret: secret,
                   authorized_keys: %{
                     storage_nonce_public_key =>
                       Crypto.ec_encrypt(aes_key, storage_nonce_public_key)
                   }
                 }
               ]
             }
           }}
      end)

      conn =
        post(conn, "/api", %{
          "query" => "query {
            token(address: \"#{Base.encode16(token_addr)}\") {
              ownerships {
                secret
                authorizedPublicKeys {
                  encryptedSecretKey
                  publicKey
                }
              }
            }
           }"
        })

      assert %{
               "data" => %{
                 "token" => %{
                   "ownerships" => [
                     %{
                       "authorizedPublicKeys" => [
                         %{
                           "encryptedSecretKey" => _,
                           "publicKey" => _
                         }
                       ],
                       "secret" => _
                     }
                   ]
                 }
               }
             } = json_response(conn, 200)
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
    test "should handle order flag and pass it to get transaction function", %{conn: conn} do
      first = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      last = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      transactions = [
        %Transaction{
          address: first,
          type: :transfer,
          data: %TransactionData{}
        },
        %Transaction{
          address: last,
          type: :hosting,
          data: %TransactionData{}
        }
      ]

      order = :desc

      order_str =
        order
        |> to_string()
        |> String.upcase()

      MockClient
      |> stub(:send_message, fn
        _, %GetTransactionChain{order: given_order}, _ ->
          assert given_order == order

          {:ok,
           %TransactionList{
             transactions: transactions
           }}

        _, %GetTransactionChainLength{}, _ ->
          %TransactionChainLength{length: 1}

        _, %GetFirstAddress{}, _ ->
          {:ok, %NotFound{}}
      end)

      conn =
        post(conn, "/api", %{
          "query" =>
            "query { transactionChain(address: \"#{Base.encode16(last)}\", order: #{order_str}) { type } }"
        })

      assert %{"data" => %{"transactionChain" => _recv_transactions}} = json_response(conn, 200)
    end

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
      |> stub(:send_message, fn
        _, %GetTransactionChain{}, _ ->
          slice_range = 1..@transaction_chain_page_size

          {:ok,
           %TransactionList{
             transactions: Enum.slice(transactions, slice_range)
           }}

        _, %GetTransactionChainLength{}, _ ->
          %TransactionChainLength{length: 1}

        _, %GetFirstAddress{}, _ ->
          {:ok, %NotFound{}}
      end)

      last_addr = List.last(transactions).address

      conn =
        post(conn, "/api", %{
          "query" =>
            "query { transactionChain(address: \"#{Base.encode16(last_addr)}\") { address } }"
        })

      assert %{"data" => %{"transactionChain" => recv_transactions}} = json_response(conn, 200)
      assert Enum.count(recv_transactions) == @transaction_chain_page_size
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

      slice_range = @transaction_chain_page_size..(2 * @transaction_chain_page_size)

      MockClient
      |> stub(:send_message, fn
        _, %GetTransactionChain{}, _ ->
          {:ok,
           %TransactionList{
             transactions: Enum.slice(transactions, slice_range)
           }}

        _, %GetTransactionChainLength{}, _ ->
          %TransactionChainLength{length: 1}

        _, %GetFirstAddress{}, _ ->
          {:ok, %NotFound{}}
      end)

      last_addr = List.last(transactions).address
      last_addr = Base.encode16(last_addr)

      first_addr = List.first(transactions).address
      first_addr = Base.encode16(first_addr)

      conn =
        post(conn, "/api", %{
          "query" =>
            "query { transactionChain(address: \"#{last_addr}\", pagingAddress: \"#{first_addr}\") { address } }"
        })

      assert %{"data" => %{"transactionChain" => recv_transactions}} = json_response(conn, 200)
      assert Enum.count(recv_transactions) == @transaction_chain_page_size

      assert Enum.slice(transactions, slice_range)
             |> Enum.map(&%{"address" => Base.encode16(&1.address)}) == recv_transactions
    end

    test "should return error on 0 length address argument", %{conn: conn} do
      conn =
        post(conn, "/api", %{
          "query" => "query { transactionChain(address: \"\") { address } }"
        })

      %{"errors" => [%{"message" => message}]} = json_response(conn, 200)
      assert message |> String.starts_with?("Argument \"address\" has invalid value \"\"")
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

      assert %{"data" => %{"balance" => %{"uco" => 218_000_000}}} = json_response(conn, 200)
    end

    test "should retrieve the token balance of an address", %{conn: conn} do
      addr = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      MockClient
      |> stub(:send_message, fn _, %GetBalance{}, _ ->
        {:ok,
         %Balance{
           token: %{
             {"@Token1", 0} => 200_000_000,
             {"@Token2", 0} => 500_000_000,
             {"@Token3", 0} => 1_000_000_000
           }
         }}
      end)

      conn =
        post(conn, "/api", %{
          "query" => "query { balance(address: \"#{Base.encode16(addr)}\") { token { amount } } }"
        })

      assert %{
               "data" => %{
                 "balance" => %{
                   "token" => [
                     %{"amount" => 200_000_000},
                     %{"amount" => 500_000_000},
                     %{"amount" => 1_000_000_000}
                   ]
                 }
               }
             } = json_response(conn, 200)
    end
  end

  describe "query: genesis_address" do
    test "should return the genesis address", %{conn: conn} do
      addr = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      genesis_addr = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      MockClient
      |> stub(:send_message, fn _, %GetFirstAddress{}, _ ->
        {:ok, %FirstAddress{address: genesis_addr}}
      end)

      conn =
        post(conn, "/api", %{
          "query" => "query {
            genesisAddress(address: \"#{Base.encode16(addr)}\")
          }"
        })

      assert %{
          "data" => %{
            "genesisAddress" => genesis
          }
        } = json_response(conn, 200)

      assert genesis == Base.encode16(genesis_addr)
    end

    test "should return same address", %{conn: conn} do
      addr = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      conn =
        post(conn, "/api", %{
          "query" => "query {
            genesisAddress(address: \"#{Base.encode16(addr)}\")
          }"
        })

      assert %{
               "data" => %{
                 "genesisAddress" => genesis
               }
             } = json_response(conn, 200)

      assert genesis == Base.encode16(addr)
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
             %VersionedTransactionInput{
               input: %TransactionInput{
                 from: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
                 amount: 20_200_000,
                 type: :UCO,
                 timestamp: DateTime.from_unix!(1_614_951_694)
               },
               protocol_version: 1
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
                     "amount" => 20_200_000,
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

  describe "query: version" do
    test "should return the code, transaction and protocol version", %{conn: conn} do
      conn =
        post(conn, "/api", %{
          "query" => "query { version { code, protocol, transaction } }"
        })

      code_version = Mix.Project.config()[:version]

      transaction_version =
        Transaction.version()
        |> to_string()

      protocol_version =
        Mining.protocol_version()
        |> to_string()

      assert %{
               "data" => %{
                 "version" => %{
                   "code" => ^code_version,
                   "protocol" => ^protocol_version,
                   "transaction" => ^transaction_version
                 }
               }
             } = json_response(conn, 200)
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

  test "should fail to connect if node is bootstraping" do
    :persistent_term.put(:archethic_up, nil)

    assert_raise MatchError, fn -> get_socket() end
  end
end
