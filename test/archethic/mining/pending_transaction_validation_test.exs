defmodule Archethic.Mining.PendingTransactionValidationTest do
  use ArchethicCase, async: false

  alias Archethic.Crypto

  alias Archethic.Mining.PendingTransactionValidation

  alias Archethic.P2P
  alias Archethic.P2P.Message.FirstPublicKey
  alias Archethic.P2P.Message.GenesisAddress
  alias Archethic.P2P.Message.GetFirstPublicKey
  alias Archethic.P2P.Message.GetGenesisAddress
  alias Archethic.P2P.Message.GetTransactionSummary
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Node

  alias Archethic.Reward.Scheduler

  alias Archethic.SharedSecrets
  alias Archethic.SharedSecrets.MemTables.NetworkLookup
  alias Archethic.SharedSecrets.MemTables.OriginKeyLookup

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger

  alias Archethic.Governance.Pools.MemTable, as: PoolsMemTable
  alias TokenLedger.Transfer, as: TokenTransfer
  alias UCOLedger.Transfer, as: UCOTransfer

  import Mox
  import Mock
  import ArchethicCase

  setup do
    P2P.add_and_connect_node(%Node{
      first_public_key: Crypto.last_node_public_key(),
      network_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now(),
      geo_patch: "AAA"
    })

    MockClient
    |> stub(:send_message, fn
      _, %GetTransactionSummary{}, _ ->
        {:ok, %NotFound{}}

      _, %GetGenesisAddress{address: address}, _ ->
        {:ok, %GenesisAddress{address: address, timestamp: DateTime.utc_now()}}
    end)

    on_exit(fn ->
      Application.put_env(:archethic, Archethic.Mining.PendingTransactionValidation,
        allowed_node_key_origins: []
      )
    end)

    :ok
  end

  describe "validate_size/1" do
    test "should return :ok when the transaction size is less than 3.1MB" do
      tx = Transaction.new(:data, %TransactionData{content: :crypto.strong_rand_bytes(3_145_711)})

      assert :ok = PendingTransactionValidation.validate(tx)
    end

    test "should return  transaction data exceeds limit when the transaction size is greater than 3.1MB" do
      tx = Transaction.new(:data, %TransactionData{content: :crypto.strong_rand_bytes(3_145_728)})

      assert {:error, "Transaction data exceeds limit"} =
               PendingTransactionValidation.validate(tx)
    end
  end

  describe "validate_ownerships" do
    defp get_tx(ownership) do
      Transaction.new(:data, %TransactionData{ownerships: ownership})
    end

    test "validate conditions for ownerships" do
      assert {:error, "Invalid data type transaction - Both content & ownership are empty"} =
               PendingTransactionValidation.validate(get_tx([]))

      assert {:error, "Ownership: secret is empty"} =
               [%Ownership{secret: "", authorized_keys: %{}}]
               |> get_tx()
               |> PendingTransactionValidation.validate()

      assert {:error, "Ownership: authorized keys are empty"} =
               [%Ownership{secret: "secret", authorized_keys: %{}}]
               |> get_tx()
               |> PendingTransactionValidation.validate()

      assert {:error, "Ownership: public key is empty"} =
               [%Ownership{secret: "secret", authorized_keys: %{"" => "ecnrypted_key"}}]
               |> get_tx()
               |> PendingTransactionValidation.validate()

      assert {:error, "Ownership: encrypted key is empty"} =
               [%Ownership{secret: "secret", authorized_keys: %{"abc" => ""}}]
               |> get_tx()
               |> PendingTransactionValidation.validate()

      assert {:error, "Ownership: invalid public key"} =
               [%Ownership{secret: "secret", authorized_keys: %{"abc" => "cba"}}]
               |> get_tx()
               |> PendingTransactionValidation.validate()

      assert :ok =
               [%Ownership{secret: "secret", authorized_keys: %{<<0::272>> => "cba"}}]
               |> get_tx()
               |> PendingTransactionValidation.validate()
    end
  end

  describe "validate_contract" do
    test "parse" do
      code = ~s"""
        condition inherit: [
               uco_transfers: %{ "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3" => 1040000000 }
             ]
      """

      assert :ok =
               Transaction.new(:contract, %TransactionData{code: code})
               |> PendingTransactionValidation.validate()
    end

    test "exceeds max code size" do
      size = Application.get_env(:archethic, :transaction_data_code_max_size)
      data = :crypto.strong_rand_bytes(size + 1)

      code = ~s"""
        condition transaction: [
         content: hash(#{data}})
      ]
      """

      assert {:error, "Invalid contract type transaction , code exceed max size"} =
               Transaction.new(:contract, %TransactionData{code: code})
               |> PendingTransactionValidation.validate()
    end
  end

  describe "Data" do
    test "Should return error when both content and ownerships are empty" do
      assert {:error, "Invalid data type transaction - Both content & ownership are empty"} =
               Transaction.new(:data, %TransactionData{})
               |> PendingTransactionValidation.validate()

      assert :ok ==
               [%Ownership{secret: "secret", authorized_keys: %{<<0::272>> => "cba"}}]
               |> get_tx()
               |> PendingTransactionValidation.validate()

      assert :ok ==
               Transaction.new(:data, %TransactionData{content: "content"})
               |> PendingTransactionValidation.validate()
    end
  end

  describe "Code Approval" do
    test "should return :ok when a code approval transaction contains a proposal target and the sender is member of the technical council and not previously signed" do
      tx =
        Transaction.new(
          :code_approval,
          %TransactionData{
            recipients: ["@CodeProposal1"]
          },
          "approval_seed",
          0
        )

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: "node1",
        last_public_key: "node1",
        geo_patch: "AAA",
        network_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      assert :ok = PoolsMemTable.put_pool_member(:technical_council, tx.previous_public_key)

      MockDB
      |> expect(:get_transaction, fn _, _, _ ->
        {:ok,
         %Transaction{
           data: %TransactionData{
             content: """
             Description: My Super Description
             Changes:
             diff --git a/mix.exs b/mix.exs
             index d9d9a06..5e34b89 100644
             --- a/mix.exs
             +++ b/mix.exs
             @@ -4,7 +4,7 @@ defmodule Archethic.MixProject do
               def project do
                 [
                   app: :archethic,
             -      version: \"0.7.1\",
             +      version: \"0.7.2\",
                   build_path: \"_build\",
                   config_path: \"config/config.exs\",
                   deps_path: \"deps\",
             @@ -53,7 +53,7 @@ defmodule Archethic.MixProject do
                   {:git_hooks, \"~> 0.4.0\", only: [:test, :dev], runtime: false},
                   {:mox, \"~> 0.5.2\", only: [:test]},
                   {:stream_data, \"~> 0.4.3\", only: [:test]},
             -      {:elixir_make, \"~> 0.6.0\", only: [:dev, :test], runtime: false},
             +      {:elixir_make, \"~> 0.6.0\", only: [:dev, :test]},
                   {:logger_file_backend, \"~> 0.0.11\", only: [:dev]}
                 ]
               end
             """
           }
         }}
      end)

      MockClient
      |> stub(:send_message, fn
        _, %GetFirstPublicKey{}, _ ->
          {:ok, %FirstPublicKey{public_key: tx.previous_public_key}}

        _, %GetTransactionSummary{}, _ ->
          {:ok, %NotFound{}}
      end)

      assert :ok = PendingTransactionValidation.validate(tx)
    end
  end

  describe "Contract" do
    test "should return error when code is empty" do
      assert {:error, "Invalid contract type transaction -  code is empty"} =
               Transaction.new(:contract, %TransactionData{code: ""})
               |> PendingTransactionValidation.validate()
    end
  end

  describe "Hosting" do
    test "should return :ok when we deploy a aeweb ref transaction" do
      tx =
        Transaction.new(:hosting, %TransactionData{
          content:
            Jason.encode!(%{
              "aewebVersion" => 1,
              "metaData" => %{
                "index.html" => %{
                  "encoding" => "gzip",
                  "hash" => "abcd123",
                  "size" => 144,
                  "addresses" => [
                    Crypto.derive_keypair("seed", 0)
                    |> elem(0)
                    |> Crypto.derive_address()
                    |> Base.encode16()
                  ]
                }
              }
            })
        })

      assert :ok = PendingTransactionValidation.validate(tx, DateTime.utc_now())
    end

    test "should return :ok when we deploy a aeweb ref transaction with publicationStatus" do
      tx =
        Transaction.new(:hosting, %TransactionData{
          content:
            Jason.encode!(%{
              "aewebVersion" => 1,
              "publicationStatus" => "PUBLISHED",
              "metaData" => %{
                "index.html" => %{
                  "encoding" => "gzip",
                  "hash" => "abcd123",
                  "size" => 144,
                  "addresses" => [
                    Crypto.derive_keypair("seed", 0)
                    |> elem(0)
                    |> Crypto.derive_address()
                    |> Base.encode16()
                  ]
                }
              }
            })
        })

      assert :ok = PendingTransactionValidation.validate(tx, DateTime.utc_now())
    end

    test "should return :ok when we deploy a aeweb ref transaction (unpublished)" do
      tx =
        Transaction.new(:hosting, %TransactionData{
          content:
            Jason.encode!(%{
              "aewebVersion" => 1,
              "publicationStatus" => "UNPUBLISHED"
            })
        })

      assert :ok = PendingTransactionValidation.validate(tx, DateTime.utc_now())
    end

    test "should return :ok when we deploy a aeweb file transaction" do
      tx =
        Transaction.new(:hosting, %TransactionData{
          content:
            Jason.encode!(%{
              "index.html" => Base.url_encode64(:crypto.strong_rand_bytes(1000))
            })
        })

      assert :ok = PendingTransactionValidation.validate(tx, DateTime.utc_now())
    end

    test "should return :error when we deploy a wrong aeweb file transaction" do
      tx =
        Transaction.new(:hosting, %TransactionData{
          content:
            Jason.encode!(%{
              "index.html" => 32
            })
        })

      assert {:error, _error} = PendingTransactionValidation.validate(tx, DateTime.utc_now())
    end

    test "should return :error when we deploy a wrong aeweb ref transaction" do
      tx =
        Transaction.new(:hosting, %TransactionData{
          content:
            Jason.encode!(%{
              "wrongKey" => 1,
              "metaData" => %{
                "index.html" => %{
                  "encoding" => "gzip",
                  "hash" => "abcd123",
                  "size" => 144,
                  "addresses" => [
                    Crypto.derive_keypair("seed", 0)
                    |> elem(0)
                    |> Crypto.derive_address()
                    |> Base.encode16()
                  ]
                }
              }
            })
        })

      assert {:error, _reason} = PendingTransactionValidation.validate(tx, DateTime.utc_now())
    end

    test "should return :error when we deploy a wrong aeweb ref transaction (unpublished)" do
      tx =
        Transaction.new(:hosting, %TransactionData{
          content:
            Jason.encode!(%{
              "aewebVersion" => 1,
              "publicationStatus" => "UNPUBLISHED",
              "metaData" => %{
                "index.html" => %{
                  "encoding" => "gzip",
                  "hash" => "abcd123",
                  "size" => 144,
                  "addresses" => [
                    Crypto.derive_keypair("seed", 0)
                    |> elem(0)
                    |> Crypto.derive_address()
                    |> Base.encode16()
                  ]
                }
              }
            })
        })

      assert {:error, _error} = PendingTransactionValidation.validate(tx, DateTime.utc_now())
    end

    test "should return :error when it does not respect the schema" do
      tx =
        Transaction.new(:hosting, %TransactionData{
          content:
            Jason.encode!(%{
              "aewebVersion" => 1,
              "hello" => "world",
              "metaData" => %{
                "index.html" => %{
                  "encoding" => "gzip",
                  "hash" => "abcd123",
                  "size" => 144,
                  "addresses" => [
                    Crypto.derive_keypair("seed", 0)
                    |> elem(0)
                    |> Crypto.derive_address()
                    |> Base.encode16()
                  ]
                }
              }
            })
        })

      assert {:error, _reason} = PendingTransactionValidation.validate(tx, DateTime.utc_now())
    end
  end

  describe "Node" do
    test "should return :ok when a node transaction data content contains node endpoint information" do
      {origin_public_key, _} =
        Crypto.generate_deterministic_keypair(:crypto.strong_rand_bytes(32), :secp256r1)

      {_, ca_pv} = :crypto.generate_key(:ecdh, :secp256r1, "ca_root_key")
      <<_::8, _::8, origin_key::binary>> = origin_public_key
      certificate = Crypto.ECDSA.sign(:secp256r1, ca_pv, origin_key)

      tx =
        Transaction.new(
          :node,
          %TransactionData{
            content:
              Node.encode_transaction_content(
                {80, 20, 10, 200},
                3000,
                4000,
                :tcp,
                <<0, 0, 4, 221, 19, 74, 75, 69, 16, 50, 149, 253, 24, 115, 128, 241, 110, 118,
                  139, 7, 48, 217, 58, 43, 145, 233, 77, 125, 190, 207, 31, 64, 157, 137>>,
                origin_public_key,
                certificate
              )
          },
          "seed",
          0
        )

      MockDB
      |> stub(:get_last_chain_address, fn address ->
        address
      end)
      |> stub(:get_transaction, fn _address, [:address, :type], _ ->
        {:error, :transaction_not_exists}
      end)

      assert :ok = PendingTransactionValidation.validate(tx)
    end

    test "should return an error when a node transaction public key used on non allowed origin" do
      Application.put_env(:archethic, Archethic.Mining.PendingTransactionValidation,
        allowed_node_key_origins: [:tpm]
      )

      {public_key, private_key} = Crypto.derive_keypair("seed", 0)
      {next_public_key, _} = Crypto.derive_keypair("seed", 1)
      certificate = Crypto.get_key_certificate(public_key)

      tx =
        Transaction.new_with_keys(
          :node,
          %TransactionData{
            content:
              Node.encode_transaction_content(
                {80, 20, 10, 200},
                3000,
                4000,
                :tcp,
                <<0, 0, 4, 221, 19, 74, 75, 69, 16, 50, 149, 253, 24, 115, 128, 241, 110, 118,
                  139, 7, 48, 217, 58, 43, 145, 233, 77, 125, 190, 207, 31, 64, 157, 137>>,
                <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
                certificate
              )
          },
          private_key,
          public_key,
          next_public_key
        )

      MockDB
      |> stub(:get_last_chain_address, fn address ->
        address
      end)
      |> stub(:get_transaction, fn _address, [:address, :type], _ ->
        {:error, :transaction_not_exists}
      end)

      assert {:error, "Invalid node transaction with invalid key origin"} =
               PendingTransactionValidation.validate(tx)
    end

    test "should return an error when a node transaction content is greater than content_max_size " do
      {public_key, private_key} = Crypto.derive_keypair("seed", 0)
      {next_public_key, _} = Crypto.derive_keypair("seed", 1)
      certificate = Crypto.get_key_certificate(public_key)

      content_pretext =
        <<80, 20, 10, 200, 3000::16, 4000::16, 1, 0, 4, 221, 19, 74, 75, 69, 16, 50, 149, 253, 24,
          115, 128, 241, 110, 118, 139, 7, 48, 217, 58, 43, 145, 233, 77, 125, 190, 207, 31, 64,
          157, 137>>

      random_content = :crypto.strong_rand_bytes(4 * 1024 * 1024)

      content =
        content_pretext <> random_content <> <<byte_size(certificate)::16, certificate::binary>>

      tx =
        Transaction.new_with_keys(
          :node,
          %TransactionData{
            content: content
          },
          private_key,
          public_key,
          next_public_key
        )

      MockDB
      |> stub(:get_last_chain_address, fn address ->
        address
      end)
      |> stub(:get_transaction, fn _address, [:address, :type], _ ->
        {:error, :transaction_not_exists}
      end)

      assert {:error, "Transaction data exceeds limit"} =
               PendingTransactionValidation.validate(tx)
    end
  end

  describe "Node Shared Secrets" do
    test "should return :ok when a node shared secrets transaction data keys contains existing node public keys with first tx" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: Crypto.derive_keypair("node_key1", 0) |> elem(1),
        last_public_key: Crypto.derive_keypair("node_key1", 1) |> elem(1),
        available?: true
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: Crypto.derive_keypair("node_key2", 0) |> elem(1),
        last_public_key: Crypto.derive_keypair("node_key2", 1) |> elem(1),
        available?: true
      })

      MockDB
      |> expect(:get_latest_tps, fn -> 1000.0 end)

      tx =
        Transaction.new(
          :node_shared_secrets,
          %TransactionData{
            content:
              <<0, 0, 219, 82, 144, 35, 140, 59, 161, 231, 225, 145, 111, 203, 173, 197, 200, 150,
                213, 145, 87, 209, 98, 25, 28, 148, 198, 77, 174, 48, 16, 117, 253, 15, 0, 0, 105,
                113, 238, 128, 201, 90, 172, 230, 46, 99, 215, 130, 104, 26, 196, 222, 157, 89,
                101, 74, 248, 245, 118, 36, 194, 213, 108, 141, 175, 248, 6, 120>>,
            code: """
            condition inherit: [
              type: node_shared_secrets
            ]
            """,
            ownerships: [
              %Ownership{
                secret: :crypto.strong_rand_bytes(32),
                authorized_keys: %{
                  (Crypto.derive_keypair("node_key1", 0) |> elem(1)) => "a_encrypted_key",
                  (Crypto.derive_keypair("node_key2", 0) |> elem(1)) => "a_encrypted_key",
                  # we started and connected this node in setup
                  Crypto.last_node_public_key() => "a_encrypted_key"
                }
              }
            ]
          }
        )

      :persistent_term.put(:node_shared_secrets_gen_addr, Transaction.previous_address(tx))
      :persistent_term.put(:node_shared_secrets_gen_addr, Transaction.previous_address(tx))
      assert :ok = PendingTransactionValidation.validate(tx)
      :persistent_term.put(:node_shared_secrets_gen_addr, nil)
    end

    test "should return error when authorized nodes are not the same as the candidates" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: "node_key1",
        last_public_key: "node_key1",
        available?: true
      })

      MockDB
      |> expect(:get_latest_tps, fn -> 1000.0 end)

      tx =
        Transaction.new(
          :node_shared_secrets,
          %TransactionData{
            content:
              <<0, 0, 219, 82, 144, 35, 140, 59, 161, 231, 225, 145, 111, 203, 173, 197, 200, 150,
                213, 145, 87, 209, 98, 25, 28, 148, 198, 77, 174, 48, 16, 117, 253, 15, 0, 0, 105,
                113, 238, 128, 201, 90, 172, 230, 46, 99, 215, 130, 104, 26, 196, 222, 157, 89,
                101, 74, 248, 245, 118, 36, 194, 213, 108, 141, 175, 248, 6, 120>>,
            code: """
            condition inherit: [
              type: node_shared_secrets
            ]
            """,
            ownerships: [
              %Ownership{
                secret: :crypto.strong_rand_bytes(32),
                authorized_keys: %{
                  # we started and connected this node in setup
                  Crypto.last_node_public_key() => :crypto.strong_rand_bytes(32)
                }
              }
            ]
          }
        )

      :persistent_term.put(:node_shared_secrets_gen_addr, Transaction.previous_address(tx))

      assert {:error, "Invalid node shared secrets transaction authorized nodes"} =
               PendingTransactionValidation.validate(tx)

      :persistent_term.put(:node_shared_secrets_gen_addr, nil)
    end

    test "should return error when there is already a node shared secrets transaction since the last schedule" do
      MockDB
      |> expect(:get_last_chain_address, fn _, _ ->
        {"OtherAddress", DateTime.utc_now()}
      end)

      tx =
        Transaction.new(
          :node_shared_secrets,
          %TransactionData{
            content: :crypto.strong_rand_bytes(32),
            ownerships: [
              %Ownership{
                secret: :crypto.strong_rand_bytes(32),
                authorized_keys: %{
                  <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>> =>
                    :crypto.strong_rand_bytes(32)
                }
              }
            ]
          },
          "seed",
          0
        )

      assert {:error, "Invalid node shared secrets trigger time"} =
               PendingTransactionValidation.validate(tx, ~U[2022-01-01 00:00:03Z])
    end
  end

  describe "Oracle" do
    test "should return error when there is already a oracle transaction since the last schedule" do
      MockDB
      |> expect(:get_last_chain_address, fn _, _ ->
        {"OtherAddress", DateTime.utc_now()}
      end)

      tx = Transaction.new(:oracle, %TransactionData{}, "seed", 0)

      assert {:error, "Invalid oracle trigger time"} =
               PendingTransactionValidation.validate(tx, ~U[2022-01-01 00:10:03Z])
    end
  end

  describe "Origin" do
    test "should return :ok when a origin transaction is made" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: "node_key1",
        last_public_key: "node_key1",
        available?: true
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: "node_key2",
        last_public_key: "node_key2",
        available?: true
      })

      {public_key, _} = Crypto.derive_keypair("random", 0)
      certificate = Crypto.get_key_certificate(public_key)
      certificate_size = byte_size(certificate)

      tx =
        Transaction.new(
          :origin,
          %TransactionData{
            code: """
            condition inherit: [
              type: origin,
              content: true
            ]
            """,
            content: <<public_key::binary, certificate_size::16, certificate::binary>>
          }
        )

      :persistent_term.put(:origin_gen_addr, [Transaction.previous_address(tx)])
      assert :ok = PendingTransactionValidation.validate(tx)
      :persistent_term.put(:origin_gen_addr, nil)
    end

    test "should return :error when a origin transaction contains existing Origin Public key" do
      OriginKeyLookup.start_link([])

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: "node_key1",
        last_public_key: "node_key1",
        available?: true
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: "node_key2",
        last_public_key: "node_key2",
        available?: true
      })

      {public_key, _} = Crypto.derive_keypair("has_origin_public_key", 0)
      OriginKeyLookup.add_public_key(:software, public_key)
      certificate = Crypto.get_key_certificate(public_key)
      certificate_size = byte_size(certificate)

      assert true == SharedSecrets.has_origin_public_key?(public_key)

      tx =
        Transaction.new(
          :origin,
          %TransactionData{
            code: """
            condition inherit: [
              type: origin,
              content: true
            ]
            """,
            content: <<public_key::binary, certificate_size::16, certificate::binary>>
          }
        )

      :persistent_term.put(:origin_gen_addr, [Transaction.previous_address(tx)])

      assert {:error, "Invalid Origin transaction Public Key Already Exists"} =
               PendingTransactionValidation.validate(tx)

      :persistent_term.put(:origin_gen_addr, nil)
    end

    test "should return :ok when a origin transaction contains new Origin Public key" do
      OriginKeyLookup.start_link([])

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: "node_key1",
        last_public_key: "node_key1",
        available?: true
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: "node_key2",
        last_public_key: "node_key2",
        available?: true
      })

      {public_key, _} = Crypto.derive_keypair("does_not_have_origin_public_key2", 0)
      certificate = Crypto.get_key_certificate(public_key)
      certificate_size = byte_size(certificate)

      assert false == SharedSecrets.has_origin_public_key?(public_key)

      tx =
        Transaction.new(
          :origin,
          %TransactionData{
            code: """
            condition inherit: [
              type: origin,
              content: true
            ]
            """,
            content: <<public_key::binary, certificate_size::16, certificate::binary>>
          }
        )

      :persistent_term.put(:origin_gen_addr, [Transaction.previous_address(tx)])

      assert :ok = PendingTransactionValidation.validate(tx)

      :persistent_term.put(:origin_gen_addr, nil)
    end
  end

  describe "Reward" do
    test "should return :ok when a mint reward transaction passes all tests" do
      tx_seed = :crypto.strong_rand_bytes(32)
      {pub, _} = Crypto.derive_keypair(tx_seed, 1)
      address = Crypto.derive_address(pub)

      NetworkLookup.set_network_pool_address(address)

      {:ok, pid} = Scheduler.start_link(interval: "0 * * * * *")

      assert {:idle, %{interval: "0 * * * * *"}} = :sys.get_state(pid)

      send(pid, :node_up)

      assert {:scheduled, %{interval: "0 * * * * *"}} = :sys.get_state(pid)

      MockDB
      |> stub(:get_latest_burned_fees, fn -> 300_000_000 end)
      |> stub(:get_last_chain_address, fn _, _ -> {address, DateTime.utc_now()} end)
      |> stub(:get_last_chain_address, fn _ -> {address, DateTime.utc_now()} end)

      tx =
        Transaction.new(
          :mint_rewards,
          %TransactionData{
            content:
              Jason.encode!(%{
                supply: 300_000_000,
                name: "MyToken",
                type: "fungible",
                symbol: "MTK"
              })
          },
          tx_seed,
          0
        )

      :persistent_term.put(:reward_gen_addr, Transaction.previous_address(tx))
      assert :ok = PendingTransactionValidation.validate(tx)
      :persistent_term.put(:reward_gen_addr, nil)
    end

    test "should return :error when a mint reward transaction has != burned_fees" do
      tx_seed = :crypto.strong_rand_bytes(32)
      {pub, _} = Crypto.derive_keypair(tx_seed, 1)
      address = Crypto.derive_address(pub)

      NetworkLookup.set_network_pool_address(address)

      {:ok, pid} = Scheduler.start_link(interval: "0 * * * * *")

      assert {:idle, %{interval: "0 * * * * *"}} = :sys.get_state(pid)

      send(pid, :node_up)

      assert {:scheduled, %{interval: "0 * * * * *"}} = :sys.get_state(pid)

      MockDB
      |> stub(:get_latest_burned_fees, fn -> 200_000_000 end)
      |> stub(:get_last_chain_address, fn _, _ -> {address, DateTime.utc_now()} end)
      |> stub(:get_last_chain_address, fn _ -> {address, DateTime.utc_now()} end)

      tx =
        Transaction.new(
          :mint_rewards,
          %TransactionData{
            content:
              Jason.encode!(%{
                supply: 300_000_000,
                name: "MyToken",
                type: "fungible",
                symbol: "MTK"
              })
          },
          tx_seed,
          0
        )

      assert {:error, "The supply do not match burned fees from last summary"} =
               PendingTransactionValidation.validate(tx)
    end

    test "should return :error when there is already a mint rewards transaction since last schedule" do
      tx_seed = :crypto.strong_rand_bytes(32)
      {pub, _} = Crypto.derive_keypair(tx_seed, 1)
      address = Crypto.derive_address(pub)

      NetworkLookup.set_network_pool_address(:crypto.strong_rand_bytes(32))

      {:ok, pid} = Scheduler.start_link(interval: "0 * * * * *")

      assert {:idle, %{interval: "0 * * * * *"}} = :sys.get_state(pid)

      send(pid, :node_up)

      assert {:scheduled, %{interval: "0 * * * * *"}} = :sys.get_state(pid)

      MockDB
      |> stub(:get_latest_burned_fees, fn -> 300_000_000 end)
      |> stub(:get_last_chain_address, fn _, _ -> {address, DateTime.utc_now()} end)

      tx =
        Transaction.new(
          :mint_rewards,
          %TransactionData{
            content:
              Jason.encode!(%{
                supply: 300_000_000,
                name: "MyToken",
                type: "fungible",
                symbol: "MTK"
              })
          },
          tx_seed,
          0
        )

      assert {:error, "There is already a mint rewards transaction since last schedule"} =
               PendingTransactionValidation.validate(tx)
    end

    test "should return error when there is already a node rewards transaction since the last schedule" do
      MockDB
      |> expect(:get_last_chain_address, fn _, _ ->
        {"OtherAddress", DateTime.utc_now()}
      end)
      |> expect(:get_transaction, fn _, _, _ ->
        {:ok, %Transaction{type: :node_rewards}}
      end)

      tx =
        Transaction.new(
          :node_rewards,
          %TransactionData{},
          "seed",
          0
        )

      assert {:error, "Invalid node rewards trigger time"} =
               PendingTransactionValidation.validate(tx, ~U[2022-01-01 00:00:03Z])
    end
  end

  describe "token" do
    test "should return :ok when a transaction contains valid fields for token creation" do
      tx_seed = :crypto.strong_rand_bytes(32)

      tx =
        Transaction.new(
          :token,
          %TransactionData{
            content:
              Jason.encode!(%{
                supply: 300_000_000,
                name: "MyToken",
                type: "non-fungible",
                symbol: "MTK",
                properties: %{
                  global: "property"
                },
                collection: [
                  %{image: "link", value: "link"},
                  %{image: "link", value: "link"},
                  %{image: "link", value: "link"}
                ]
              })
          },
          tx_seed,
          0
        )

      assert :ok = PendingTransactionValidation.validate(tx)
    end

    test "should return ok with a token creation with allow_mint flag" do
      tx_seed = :crypto.strong_rand_bytes(32)

      tx =
        Transaction.new(
          :token,
          %TransactionData{
            content:
              Jason.encode!(%{
                aeip: [2, 18],
                supply: 100_000_000_000,
                decimals: 8,
                name: "CoinCoin",
                type: "fungible",
                symbol: "CC",
                allow_mint: true
              })
          },
          tx_seed,
          0
        )

      assert :ok = PendingTransactionValidation.validate(tx)
    end

    test "should return ok with a valid token resupply" do
      tx_seed = :crypto.strong_rand_bytes(32)
      address = random_address()
      genesis_address = random_address()

      tx =
        Transaction.new(
          :token,
          %TransactionData{
            content:
              Jason.encode!(%{
                supply: 100_000_000_000,
                aeip: [2, 18],
                token_reference: address |> Base.encode16()
              })
          },
          tx_seed,
          0
        )

      with_mock(
        TransactionChain,
        [:passthrough],
        fetch_genesis_address: fn _, _ ->
          {:ok, genesis_address}
        end,
        fetch_transaction: fn _, _ ->
          {:ok,
           %Transaction{
             data: %TransactionData{
               content: """
               {
                "supply": 10000000000,
                "type": "fungible",
                "decimals": 8,
                "name": "CoinCoin",
                "allow_mint": true,
                "aeip": [2, 18]
               }
               """
             }
           }}
        end
      ) do
        assert :ok = PendingTransactionValidation.validate(tx)
        assert_called_exactly(TransactionChain.fetch_genesis_address(:_, :_), 2)
      end
    end

    test "should return error if not in the same chain" do
      tx_seed = :crypto.strong_rand_bytes(32)
      address = random_address()
      genesis_address = random_address()
      genesis_address2 = random_address()

      tx =
        Transaction.new(
          :token,
          %TransactionData{
            content:
              Jason.encode!(%{
                supply: 100_000_000_000,
                aeip: [2, 18],
                token_reference: address |> Base.encode16()
              })
          },
          tx_seed,
          0
        )

      with_mock(
        TransactionChain,
        [:passthrough],
        fetch_genesis_address: fn
          ^address, _ ->
            {:ok, genesis_address}

          _, _ ->
            {:ok, genesis_address2}
        end,
        fetch_transaction: fn _, _ ->
          {:ok,
           %Transaction{
             data: %TransactionData{
               content: """
               {
                "supply": 10000000000,
                "type": "fungible",
                "decimals": 8,
                "name": "CoinCoin",
                "allow_mint": true,
                "aeip": [2, 18]
               }
               """
             }
           }}
        end
      ) do
        assert {:error,
                "Invalid token transaction - token_reference is not in the same transaction chain"} =
                 PendingTransactionValidation.validate(tx)

        assert_called_exactly(TransactionChain.fetch_genesis_address(:_, :_), 2)
      end
    end

    test "should return error if allow_mint is not true" do
      tx_seed = :crypto.strong_rand_bytes(32)
      address = random_address()
      genesis_address = random_address()

      tx =
        Transaction.new(
          :token,
          %TransactionData{
            content:
              Jason.encode!(%{
                supply: 100_000_000_000,
                aeip: [2, 18],
                token_reference: address |> Base.encode16()
              })
          },
          tx_seed,
          0
        )

      with_mock(
        TransactionChain,
        [:passthrough],
        fetch_genesis_address: fn
          _, _ ->
            {:ok, genesis_address}
        end,
        fetch_transaction: fn _, _ ->
          {:ok,
           %Transaction{
             data: %TransactionData{
               content: """
               {
                "supply": 10000000000,
                "type": "fungible",
                "decimals": 8,
                "name": "CoinCoin",
                "aeip": [2, 18]
               }
               """
             }
           }}
        end
      ) do
        assert {:error,
                "Invalid token transaction - token_reference does not have allow_mint: true"} =
                 PendingTransactionValidation.validate(tx)

        assert_called_exactly(TransactionChain.fetch_genesis_address(:_, :_), 2)
      end
    end

    test "should return error if token is non-fungible" do
      tx_seed = :crypto.strong_rand_bytes(32)
      address = random_address()
      genesis_address = random_address()

      tx =
        Transaction.new(
          :token,
          %TransactionData{
            content:
              Jason.encode!(%{
                supply: 100_000_000_000,
                aeip: [2, 18],
                token_reference: address |> Base.encode16()
              })
          },
          tx_seed,
          0
        )

      with_mock(
        TransactionChain,
        [:passthrough],
        fetch_genesis_address: fn
          _, _ ->
            {:ok, genesis_address}
        end,
        fetch_transaction: fn _, _ ->
          {:ok,
           %Transaction{
             data: %TransactionData{
               content: """
               {
                "supply": 300000000,
                "name": "My NFT",
                "type": "non-fungible",
                "symbol": "MNFT",
                "properties": {
                   "description": "this property is for all NFT"
                },
                "collection": [
                   { "image": "link of the 1st NFT image" },
                   { "image": "link of the 2nd NFT image" },
                   {
                      "image": "link of the 3rd NFT image",
                      "other_property": "other value"
                   }
                ]
               }
               """
             }
           }}
        end
      ) do
        assert {:error, "Invalid token transaction - token_reference must be fungible"} =
                 PendingTransactionValidation.validate(tx)

        assert_called_exactly(TransactionChain.fetch_genesis_address(:_, :_), 2)
      end
    end

    test "should return error if token reference does not exist" do
      tx_seed = :crypto.strong_rand_bytes(32)
      address = random_address()
      genesis_address = random_address()

      tx =
        Transaction.new(
          :token,
          %TransactionData{
            content:
              Jason.encode!(%{
                supply: 100_000_000_000,
                aeip: [2, 18],
                token_reference: address |> Base.encode16()
              })
          },
          tx_seed,
          0
        )

      with_mock(
        TransactionChain,
        [:passthrough],
        fetch_genesis_address: fn
          _, _ ->
            {:ok, genesis_address}
        end,
        fetch_transaction: fn _, _ ->
          {:error, :transaction_not_exists}
        end
      ) do
        assert {:error, "Invalid token transaction - token_reference not found"} =
                 PendingTransactionValidation.validate(tx)

        assert_called_exactly(TransactionChain.fetch_genesis_address(:_, :_), 2)
      end
    end

    test "should return error if token reference is not a proper token definition" do
      tx_seed = :crypto.strong_rand_bytes(32)
      address = random_address()
      genesis_address = random_address()

      tx =
        Transaction.new(
          :token,
          %TransactionData{
            content:
              Jason.encode!(%{
                supply: 100_000_000_000,
                aeip: [2, 18],
                token_reference: address |> Base.encode16()
              })
          },
          tx_seed,
          0
        )

      with_mock(
        TransactionChain,
        [:passthrough],
        fetch_genesis_address: fn
          _, _ ->
            {:ok, genesis_address}
        end,
        fetch_transaction: fn _, _ ->
          {:ok,
           %Transaction{
             data: %TransactionData{
               content: """
               not a json
               """
             }
           }}
        end
      ) do
        assert {:error,
                "Invalid token transaction - token_reference exists but does not contain a valid JSON"} =
                 PendingTransactionValidation.validate(tx)

        assert_called_exactly(TransactionChain.fetch_genesis_address(:_, :_), 2)
      end
    end

    test "should return error if token reference is not hexadecimal" do
      tx_seed = :crypto.strong_rand_bytes(32)

      tx =
        Transaction.new(
          :token,
          %TransactionData{
            content:
              Jason.encode!(%{
                supply: 100_000_000_000,
                aeip: [2, 18],
                token_reference: "invalidtokenref"
              })
          },
          tx_seed,
          0
        )

      assert {:error, "Invalid token transaction - neither a token creation nor a token resupply"} =
               PendingTransactionValidation.validate(tx)
    end

    test "should return error if token transaction is incorrect" do
      tx_seed = :crypto.strong_rand_bytes(32)

      tx =
        Transaction.new(
          :token,
          %TransactionData{
            content: Jason.encode!(%{})
          },
          tx_seed,
          0
        )

      assert {:error, "Invalid token transaction - neither a token creation nor a token resupply"} =
               PendingTransactionValidation.validate(tx)
    end
  end

  describe "transfer" do
    test "should return :ok when a transaction contains a valid smart contract code" do
      tx_seed = :crypto.strong_rand_bytes(32)

      tx =
        Transaction.new(
          :transfer,
          %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: [
                  %UCOTransfer{to: :crypto.strong_rand_bytes(32), amount: 100_000}
                ]
              }
            },
            code: """
            condition inherit: [
              content: "hello"
            ]

            condition transaction: [
              content: ""
            ]

            actions triggered_by: transaction do
              set_content "hello"
            end
            """,
            ownerships: [
              Ownership.new(tx_seed, :crypto.strong_rand_bytes(32), [
                Crypto.storage_nonce_public_key()
              ])
            ]
          },
          tx_seed,
          0
        )

      assert :ok = PendingTransactionValidation.validate(tx)
    end
  end

  describe "Keychain Transaction" do
    test "should reject empty content in keychain transaction" do
      tx_seed = :crypto.strong_rand_bytes(32)

      tx =
        Transaction.new(
          :keychain,
          %TransactionData{
            content: ""
          },
          tx_seed,
          0
        )

      assert {:error, "Invalid Keychain transaction"} = PendingTransactionValidation.validate(tx)
    end

    test "Should Reject keychain tx with empty Ownerships list in keychain transaction" do
      tx_seed = :crypto.strong_rand_bytes(32)

      tx =
        Transaction.new(
          :keychain,
          %TransactionData{
            content: "content",
            ownerships: []
          },
          tx_seed,
          0
        )

      assert {:error, "Invalid Keychain transaction"} = PendingTransactionValidation.validate(tx)
    end

    test "Should Reject keychain tx with UCO tranfers" do
      tx_seed = :crypto.strong_rand_bytes(32)

      tx =
        Transaction.new(
          :keychain,
          %TransactionData{
            content: "content",
            ownerships: [
              Ownership.new(tx_seed, :crypto.strong_rand_bytes(32), [
                Crypto.storage_nonce_public_key()
              ])
            ],
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: [
                  %UCOTransfer{to: :crypto.strong_rand_bytes(32), amount: 100_000}
                ]
              }
            }
          },
          tx_seed,
          0
        )

      assert {:error, "Invalid Keychain transaction"} = PendingTransactionValidation.validate(tx)

      tx =
        Transaction.new(
          :keychain,
          %TransactionData{
            content: "content",
            ownerships: [
              Ownership.new(tx_seed, :crypto.strong_rand_bytes(32), [
                Crypto.storage_nonce_public_key()
              ])
            ],
            ledger: %Ledger{
              token: %TokenLedger{
                transfers: [
                  %TokenTransfer{
                    to: :crypto.strong_rand_bytes(32),
                    amount: 100_000_000,
                    token_address: "0123"
                  }
                ]
              }
            }
          },
          tx_seed,
          0
        )

      assert {:error, "Invalid Keychain transaction"} = PendingTransactionValidation.validate(tx)

      tx =
        Transaction.new(
          :keychain,
          %TransactionData{
            content: "content",
            ownerships: [
              Ownership.new(tx_seed, :crypto.strong_rand_bytes(32), [
                Crypto.storage_nonce_public_key()
              ])
            ],
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: [
                  %UCOTransfer{to: :crypto.strong_rand_bytes(32), amount: 100_000}
                ]
              },
              token: %TokenLedger{
                transfers: [
                  %TokenTransfer{
                    to: :crypto.strong_rand_bytes(32),
                    amount: 100_000_000,
                    token_address: "0123"
                  }
                ]
              }
            }
          },
          tx_seed,
          0
        )

      assert {:error, "Invalid Keychain transaction"} = PendingTransactionValidation.validate(tx)
    end
  end

  describe "Keychain Acesss Transaction" do
    test "should reject tx with more than one ownership" do
      tx_seed = :crypto.strong_rand_bytes(32)

      tx =
        Transaction.new(
          :keychain_access,
          %TransactionData{
            ownerships: [
              Ownership.new(tx_seed, :crypto.strong_rand_bytes(32), [
                Crypto.storage_nonce_public_key()
              ]),
              Ownership.new(tx_seed, :crypto.strong_rand_bytes(32), [
                Crypto.storage_nonce_public_key()
              ])
            ]
          },
          tx_seed,
          0
        )

      assert {:error, "Invalid Keychain Access transaction"} =
               PendingTransactionValidation.validate(tx)

      tx =
        Transaction.new(
          :keychain_access,
          %TransactionData{
            ownerships: []
          },
          tx_seed,
          0
        )

      assert {:error, "Invalid Keychain Access transaction"} =
               PendingTransactionValidation.validate(tx)

      tx =
        Transaction.new(
          :keychain_access,
          %TransactionData{
            content: "content",
            ownerships: [
              Ownership.new(tx_seed, :crypto.strong_rand_bytes(32), [
                Crypto.storage_nonce_public_key()
              ])
            ]
          },
          tx_seed,
          0
        )

      assert {:error, "Invalid Keychain Access transaction"} =
               PendingTransactionValidation.validate(tx)

      tx =
        Transaction.new(
          :keychain_access,
          %TransactionData{
            content: "",
            ownerships: [
              Ownership.new(tx_seed, :crypto.strong_rand_bytes(32), [
                Crypto.storage_nonce_public_key()
              ])
            ]
          },
          tx_seed,
          0
        )

      assert {:error,
              "Invalid Keychain access transaction - Previous public key must be authorized"} =
               PendingTransactionValidation.validate(tx)

      tx =
        Transaction.new(
          :keychain_access,
          %TransactionData{
            recipients: ["sendtoSAM"],
            content: "",
            ownerships: [
              Ownership.new(tx_seed, :crypto.strong_rand_bytes(32), [
                Crypto.storage_nonce_public_key()
              ])
            ]
          },
          tx_seed,
          0
        )

      assert {:error, "Invalid Keychain Access transaction"} =
               PendingTransactionValidation.validate(tx)
    end
  end
end
