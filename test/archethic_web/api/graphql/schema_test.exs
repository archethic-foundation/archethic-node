defmodule ArchethicWeb.API.GraphQL.SchemaTest do
  @moduledoc false
  use ArchethicCase
  use ArchethicWeb.ConnCase
  use ArchethicWeb.GraphQLSubscriptionCase

  alias Archethic.{Crypto, BeaconChain, P2P, TransactionChain, Mining, PubSub}

  alias BeaconChain.{ReplicationAttestation, SummaryAggregate, SummaryTimer, Summary}
  alias TransactionChain.{Transaction, TransactionData, TransactionData.Ownership}
  alias TransactionChain.{TransactionInput, TransactionSummary, VersionedTransactionInput}

  alias TransactionChain.Transaction.ValidationStamp.LedgerOperations.{
    UnspentOutput,
    VersionedUnspentOutput
  }

  alias P2P.{Node, Message}
  alias Message.{GetTransactionChainLength, TransactionChainLength, GenesisAddress}

  alias Message.{
    GetLastTransactionAddress,
    GetTransaction,
    NotFound,
    GetFirstTransactionAddress,
    FirstTransactionAddress
  }

  alias Message.{
    GetTransactionChain,
    GetTransactionInputs,
    LastTransactionAddress,
    GetGenesisAddress
  }

  alias Message.{TransactionInputList, TransactionList, GetGenesisAddress}
  alias Message.{GetBeaconSummariesAggregate, GetCurrentSummaries, GetBeaconSummaries}
  alias Message.{BeaconSummaryList, TransactionSummaryList}
  alias Message.{GetUnspentOutputs, UnspentOutputList}

  alias ArchethicWeb.API.GraphQL.Schema.Resolver

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
      authorization_date: ~U[2024-01-01 00:00:00Z],
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

    test "should return the transaction with the requested fields", %{conn: conn} do
      addr = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>> |> Base.encode16()
      prev_public_key = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      MockClient
      |> stub(:send_message, fn _, %GetTransaction{}, _ ->
        {:ok,
         %Transaction{
           address: addr,
           previous_public_key: prev_public_key,
           type: :transfer,
           data: %TransactionData{}
         }}
      end)

      conn =
        post(conn, "/api", %{
          "query" => "query { transaction(address: \"#{addr}\") { address, previousAddress } }"
        })

      assert %{
               "data" => %{
                 "transaction" => %{
                   "address" => address,
                   "previousAddress" => previous_address
                 }
               }
             } = json_response(conn, 200)

      assert addr == Base.decode16!(address, case: :mixed)

      assert Base.decode16!(previous_address) == Crypto.derive_address(prev_public_key)
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
          {:ok,
           %Transaction{
             previous_public_key: first_addr,
             address: last_address,
             type: :transfer
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
        _, %GetGenesisAddress{}, _ ->
          {:ok, %GenesisAddress{address: token_addr, timestamp: DateTime.utc_now()}}

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
        prev_addr1 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
        prev_addr2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

        [
          %Transaction{
            address: addr1,
            type: :transfer,
            previous_public_key: prev_addr1,
            data: %TransactionData{}
          },
          %Transaction{
            address: addr2,
            type: :transfer,
            previous_public_key: prev_addr2,
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
          prev_addr = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

          %Transaction{
            address: addr,
            previous_public_key: prev_addr,
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
          previous_public_key: last,
          type: :transfer,
          data: %TransactionData{}
        },
        %Transaction{
          address: last,
          previous_public_key: last,
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
          {:ok, %TransactionChainLength{length: 1}}

        _, %GetGenesisAddress{}, _ ->
          {:ok, %NotFound{}}

        _, %GetLastTransactionAddress{}, _ ->
          {:ok, %LastTransactionAddress{address: last}}
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
          prev_addr = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

          %Transaction{
            address: addr,
            type: :transfer,
            previous_public_key: prev_addr,
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
          {:ok, %TransactionChainLength{length: 1}}

        _, %GetGenesisAddress{}, _ ->
          {:ok, %NotFound{}}

        _, %GetLastTransactionAddress{}, _ ->
          {:ok, %LastTransactionAddress{address: List.last(transactions).address}}
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
          prev_addr = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

          %Transaction{
            address: addr,
            type: :transfer,
            previous_public_key: prev_addr,
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

        _, %GetGenesisAddress{}, _ ->
          {:ok, %NotFound{}}

        _, %GetLastTransactionAddress{}, _ ->
          {:ok, %LastTransactionAddress{address: List.last(transactions).address}}
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
      |> stub(:send_message, fn
        _, %GetUnspentOutputs{}, _ ->
          {:ok,
           %UnspentOutputList{
             unspent_outputs: [
               %VersionedUnspentOutput{
                 unspent_output: %UnspentOutput{
                   from: ArchethicCase.random_address(),
                   type: :UCO,
                   amount: 218_000_000
                 }
               }
             ]
           }}

        _, %GetGenesisAddress{address: address}, _ ->
          {:ok, %GenesisAddress{address: address, timestamp: DateTime.utc_now()}}
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
      |> stub(:send_message, fn
        _, %GetUnspentOutputs{}, _ ->
          {:ok,
           %UnspentOutputList{
             unspent_outputs: [
               %VersionedUnspentOutput{
                 unspent_output: %UnspentOutput{
                   type: {:token, "@Token1", 0},
                   amount: 200_000_000,
                   from: ArchethicCase.random_address()
                 }
               },
               %VersionedUnspentOutput{
                 unspent_output: %UnspentOutput{
                   type: {:token, "@Token2", 0},
                   amount: 500_000_000,
                   from: ArchethicCase.random_address()
                 }
               },
               %VersionedUnspentOutput{
                 unspent_output: %UnspentOutput{
                   type: {:token, "@Token3", 0},
                   amount: 1_000_000_000,
                   from: ArchethicCase.random_address()
                 }
               }
             ]
           }}

        _, %GetGenesisAddress{address: address}, _ ->
          {:ok, %GenesisAddress{address: address, timestamp: DateTime.utc_now()}}
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
      |> stub(:send_message, fn _, %GetGenesisAddress{}, _ ->
        {:ok, %GenesisAddress{address: genesis_addr, timestamp: DateTime.utc_now()}}
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

      MockClient
      |> stub(:send_message, fn _, %GetGenesisAddress{}, _ ->
        {:ok, %GenesisAddress{address: addr, timestamp: DateTime.utc_now()}}
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

      assert genesis == Base.encode16(addr)
    end
  end

  describe "query: transaction_inputs" do
    test "should return a list of ledger inputs combining genesis unspent outputs and tx inputs",
         %{conn: conn} do
      addr = ArchethicCase.random_address()
      from = ArchethicCase.random_address()

      MockClient
      |> stub(:send_message, fn
        _, %GetTransactionInputs{}, _ ->
          {:ok,
           %TransactionInputList{
             inputs: [
               %VersionedTransactionInput{
                 input: %TransactionInput{
                   from: from,
                   amount: 100_000_000,
                   type: :UCO,
                   timestamp: ~U[2020-01-01 00:00:00Z]
                 },
                 protocol_version: 1
               }
             ]
           }}

        _, %GetUnspentOutputs{}, _ ->
          {:ok,
           %UnspentOutputList{
             unspent_outputs: [
               %VersionedUnspentOutput{
                 unspent_output: %UnspentOutput{
                   from: from,
                   amount: 100_000_000,
                   type: :UCO,
                   timestamp: ~U[2020-01-01 00:00:00Z]
                 },
                 protocol_version: 1
               }
             ]
           }}

        _, %GetGenesisAddress{address: address}, _ ->
          {:ok, %GenesisAddress{address: address, timestamp: DateTime.utc_now()}}

        _, %GetFirstTransactionAddress{}, _ ->
          {:error, :does_not_exist}
      end)

      conn =
        post(conn, "/api", %{
          "query" =>
            "query { transaction_inputs(address: \"#{Base.encode16(addr)}\") { type, amount, spent } }"
        })

      assert %{
               "data" => %{
                 "transaction_inputs" => [
                   %{
                     "type" => "UCO",
                     "amount" => 100_000_000,
                     "spent" => false
                   }
                 ]
               }
             } = json_response(conn, 200)
    end

    test "should return flag tx input as spent if not present in the genesis", %{conn: conn} do
      addr = ArchethicCase.random_address()
      from = ArchethicCase.random_address()

      MockClient
      |> stub(:send_message, fn
        _, %GetTransactionInputs{}, _ ->
          {:ok,
           %TransactionInputList{
             inputs: [
               %VersionedTransactionInput{
                 input: %TransactionInput{
                   from: from,
                   amount: 100_000_000,
                   type: :UCO,
                   timestamp: ~U[2020-01-01 00:00:00Z]
                 },
                 protocol_version: 1
               }
             ]
           }}

        _, %GetUnspentOutputs{}, _ ->
          {:ok,
           %UnspentOutputList{
             unspent_outputs: [
               %VersionedUnspentOutput{
                 unspent_output: %UnspentOutput{
                   from: ArchethicCase.random_address(),
                   amount: 500_000_000,
                   type: :UCO,
                   timestamp: ~U[2020-10-01 00:00:00Z]
                 },
                 protocol_version: 1
               }
             ]
           }}

        _, %GetGenesisAddress{address: address}, _ ->
          {:ok, %GenesisAddress{address: address, timestamp: DateTime.utc_now()}}

        _, %GetFirstTransactionAddress{address: address}, _ ->
          {:ok, %FirstTransactionAddress{address: address, timestamp: DateTime.utc_now()}}
      end)

      conn =
        post(conn, "/api", %{
          "query" =>
            "query { transaction_inputs(address: \"#{Base.encode16(addr)}\") { type, amount, spent } }"
        })

      assert %{
               "data" => %{
                 "transaction_inputs" => [
                   %{
                     "type" => "UCO",
                     "amount" => 100_000_000,
                     "spent" => true
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

  describe "query: beacon_chain_summary" do
    test "should return error when next summary of timestamp is greater than next current time summary time",
         %{conn: conn} do
      timestamp =
        DateTime.utc_now()
        |> DateTime.add(1, :hour)
        |> DateTime.to_unix()

      conn =
        post(conn, "/api", %{
          "query" => "query { beaconChainSummary(timestamp: #{timestamp}) {version} }"
        })

      assert %{
               "errors" => [
                 %{
                   "message" => "No data found at this date !"
                 }
               ]
             } = json_response(conn, 200)
    end

    test "should call fetch_summaries_aggregate when next summary of timestamp is previous last summary date",
         %{
           conn: conn
         } do
      # SummaryTimer every hour
      Application.put_env(:archethic, SummaryTimer, interval: "0 0 */1 * * * *")

      past_summary_time =
        DateTime.utc_now() |> SummaryTimer.previous_summary() |> SummaryTimer.previous_summary()

      past_summary_timestamp = DateTime.to_unix(past_summary_time)

      timestamp = past_summary_time |> DateTime.add(-5, :minute) |> DateTime.to_unix()

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3004,
        first_public_key: "test",
        last_public_key: "test",
        available?: true
      })

      MockClient
      |> expect(:send_message, fn
        _, %GetBeaconSummariesAggregate{date: ^past_summary_time}, _ ->
          {:ok, %SummaryAggregate{summary_time: past_summary_time}}
      end)

      conn =
        post(conn, "/api", %{
          "query" => "query { beaconChainSummary(timestamp: #{timestamp}) {summaryTime} }"
        })

      assert %{
               "data" => %{
                 "beaconChainSummary" => %{
                   "summaryTime" => ^past_summary_timestamp
                 }
               }
             } = json_response(conn, 200)
    end

    test "should take into account limit and offset when sending transaction_summaries", %{
      conn: conn
    } do
      Application.put_env(:archethic, SummaryTimer, interval: "* * * * * * *")

      today = DateTime.utc_now()

      timestamp =
        today
        |> DateTime.add(-1, :day)
        |> DateTime.to_unix()

      attestations =
        [
          %TransactionSummary{
            timestamp: ~U[2022-12-06 23:56:00.006Z],
            address:
              <<0, 0, 206, 240, 245, 203, 197, 124, 94, 244, 159, 116, 250, 33, 156, 45, 76, 218,
                205, 36, 102, 210, 113, 143, 12, 21, 228, 164, 14, 115, 91, 21, 80, 247>>,
            type: :oracle_summary,
            fee: 0,
            movements_addresses: []
          },
          %TransactionSummary{
            timestamp: ~U[2022-12-06 23:56:00.042Z],
            address:
              <<0, 0, 93, 87, 204, 21, 164, 60, 42, 148, 90, 78, 173, 11, 77, 189, 104, 15, 120,
                6, 54, 35, 203, 176, 246, 200, 100, 215, 101, 150, 29, 59, 225, 65>>,
            type: :oracle,
            fee: 0,
            movements_addresses: []
          },
          %TransactionSummary{
            timestamp: ~U[2022-12-06 23:56:30.865Z],
            address:
              <<0, 0, 234, 152, 107, 255, 80, 152, 50, 245, 184, 183, 134, 17, 162, 71, 41, 203,
                94, 81, 174, 188, 75, 128, 218, 110, 53, 11, 68, 5, 242, 31, 191, 202>>,
            type: :node_rewards,
            fee: 0,
            movements_addresses: [
              <<0, 0, 238, 157, 220, 82, 41, 235, 255, 225, 151, 39, 112, 88, 241, 26, 65, 226,
                34, 82, 216, 106, 144, 76, 140, 188, 243, 140, 30, 252, 66, 171, 80, 101>>
            ]
          }
        ]
        |> Enum.map(&%ReplicationAttestation{transaction_summary: &1, confirmations: []})

      str_filtered_transaction_summaries = %{
        "data" => %{
          "beaconChainSummary" => %{
            "TransactionSummaries" => [
              %{
                "address" =>
                  "0000EA986BFF509832F5B8B78611A24729CB5E51AEBC4B80DA6E350B4405F21FBFCA",
                "fee" => 0,
                "movementsAddresses" => [
                  "0000EE9DDC5229EBFFE197277058F11A41E22252D86A904C8CBCF38C1EFC42AB5065"
                ],
                "timestamp" => 1_670_370_990,
                "type" => "node_rewards"
              }
            ]
          }
        }
      }

      MockClient
      |> expect(:send_message, fn
        _, %GetBeaconSummariesAggregate{}, _ ->
          {:ok, %SummaryAggregate{replication_attestations: attestations}}
      end)

      conn =
        post(conn, "/api", %{
          "query" =>
            "query { beaconChainSummary(timestamp: #{timestamp}) {TransactionSummaries(limit: 1, pagingOffset: 2){fee, type, timestamp, address, movementsAddresses}} }"
        })

      assert str_filtered_transaction_summaries == json_response(conn, 200)
    end

    test "should call fetch_and_aggregate_summaries when next summary of timestamp is the previous summary",
         %{
           conn: conn
         } do
      # SummaryTimer every hour
      Application.put_env(:archethic, SummaryTimer, interval: "0 0 */1 * * * *")

      previous_summary_time = DateTime.utc_now() |> SummaryTimer.previous_summary()
      previous_summary_timestamp = DateTime.to_unix(previous_summary_time)
      timestamp = previous_summary_time |> DateTime.add(-5, :minute) |> DateTime.to_unix()

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3004,
        http_port: 3004,
        first_public_key: <<0::8, 0::8, 1::8, :crypto.strong_rand_bytes(31)::binary>>,
        last_public_key: "test",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-1, :day),
        network_patch: "AAA",
        geo_patch: "AAA"
      })

      # Called 26 times because addresses are chunked by batch of 10
      MockClient
      |> expect(:send_message, 26, fn
        _, %GetBeaconSummaries{}, _ ->
          {:ok,
           %BeaconSummaryList{
             summaries: [%Summary{summary_time: previous_summary_time}]
           }}
      end)

      conn =
        post(conn, "/api", %{
          "query" => "query { beaconChainSummary(timestamp: #{timestamp}) {summary_time} }"
        })

      assert %{
               "data" => %{
                 "beaconChainSummary" => %{
                   "summary_time" => ^previous_summary_timestamp
                 }
               }
             } = json_response(conn, 200)
    end

    test "should call list_transactions_summaries_from_current_slot when next summary of timestamp is over last summary date",
         %{
           conn: conn
         } do
      # SummaryTimer every hour
      Application.put_env(:archethic, SummaryTimer, interval: "0 0 */1 * * * *")

      next_summary_time = DateTime.utc_now() |> SummaryTimer.next_summary()
      next_summary_timestamp = DateTime.to_unix(next_summary_time)

      timestamp = next_summary_time |> DateTime.add(-5, :minute) |> DateTime.to_unix()

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3004,
        first_public_key: "test",
        last_public_key: "test",
        available?: true
      })

      MockClient
      |> stub(:send_message, fn
        _, %GetCurrentSummaries{}, _ ->
          {:ok, %TransactionSummaryList{transaction_summaries: []}}
      end)

      conn =
        post(conn, "/api", %{
          "query" => "query { beaconChainSummary(timestamp: #{timestamp}) {summaryTime} }"
        })

      assert %{
               "data" => %{
                 "beaconChainSummary" => %{
                   "summaryTime" => ^next_summary_timestamp
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

  describe "Nearest Endpoint" do
    test "order of return", %{conn: conn} do
      P2P.add_and_connect_node(%Node{
        ip: {101, 10, 10, 1},
        port: 40_005,
        http_port: 4005,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: "key2",
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        enrollment_date: DateTime.utc_now()
      })

      P2P.add_and_connect_node(%Node{
        ip: {100, 10, 10, 1},
        port: 40_005,
        http_port: 4005,
        first_public_key: "key2",
        last_public_key: "key2",
        network_patch: "ABC",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        enrollment_date: DateTime.utc_now()
      })

      P2P.add_and_connect_node(%Node{
        ip: {99, 10, 10, 1},
        port: 40_004,
        http_port: 40_004,
        first_public_key: "key1",
        last_public_key: "key1",
        network_patch: "E0A",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        enrollment_date: DateTime.utc_now()
      })

      P2P.add_and_connect_node(%Node{
        ip: {147, 190, 18, 11},
        port: 40_004,
        http_port: 40_004,
        first_public_key: "key3",
        last_public_key: "key3",
        network_patch: "ABB",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        enrollment_date: DateTime.utc_now()
      })

      MockGeoIP
      |> stub(:get_coordinates, fn _ ->
        {48.8583701, 2.2922926}
      end)

      ip = {98, 6, 2, 5}

      assert [
               %{ip: '101.10.10.1', port: 4_005},
               %{ip: '100.10.10.1', port: 4_005},
               %{
                 ip: '147.190.18.11',
                 port: 40_004
               },
               %{ip: '99.10.10.1', port: 40_004}
             ] = Resolver.nearest_endpoints(ip)

      conn = Map.put(conn, :remote_ip, ip)

      conn =
        post(conn, "/api", %{
          "query" => "query { nearestEndpoints{ip,port} }"
        })

      %{
        "data" => %{
          "nearestEndpoints" => [
            %{
              "ip" => "101.10.10.1",
              "port" => 4_005
            },
            %{
              "ip" => "100.10.10.1",
              "port" => 4_005
            },
            %{
              "ip" => "147.190.18.11",
              "port" => 40_004
            },
            %{
              "ip" => "99.10.10.1",
              "port" => 40_004
            }
          ]
        }
      } = json_response(conn, 200)
    end
  end
end
