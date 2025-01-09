defmodule Archethic.Mining.PendingTransactionValidationTest do
  use ArchethicCase, async: false
  import ArchethicCase

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
  alias Archethic.SharedSecrets.MemTables.OriginKeyLookup

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger

  alias Archethic.Governance.Pools.MemTable, as: PoolsMemTable
  alias TokenLedger.Transfer, as: TokenTransfer
  alias UCOLedger.Transfer, as: UCOTransfer

  alias Archethic.ContractFactory
  alias Archethic.TransactionFactory

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

  describe "validate_non_fungible_token_transfer" do
    test "should return error if nft token is not sent by unit" do
      ledger = %Ledger{
        token: %TokenLedger{
          transfers: [
            %TokenTransfer{
              to: random_address(),
              amount: 123,
              token_address: random_address(),
              token_id: 1
            }
          ]
        }
      }

      tx = TransactionFactory.create_non_valided_transaction(type: :transfer, ledger: ledger)

      assert {:error, "Non fungible token can only be sent by unit"} =
               PendingTransactionValidation.validate_non_fungible_token_transfer(tx)

      ledger = %Ledger{
        token: %TokenLedger{
          transfers: [
            %TokenTransfer{
              to: random_address(),
              amount: 200_000_000,
              token_address: random_address(),
              token_id: 1
            }
          ]
        }
      }

      tx = TransactionFactory.create_non_valided_transaction(type: :transfer, ledger: ledger)

      assert {:error, "Non fungible token can only be sent by unit"} =
               PendingTransactionValidation.validate_non_fungible_token_transfer(tx)
    end

    test "should return ok if nft token is sent in unit" do
      ledger = %Ledger{
        token: %TokenLedger{
          transfers: [
            %TokenTransfer{
              to: random_address(),
              amount: 100_000_000,
              token_address: random_address(),
              token_id: 1
            }
          ]
        }
      }

      tx = TransactionFactory.create_non_valided_transaction(type: :transfer, ledger: ledger)

      assert :ok = PendingTransactionValidation.validate_non_fungible_token_transfer(tx)
    end

    test "should return ok if fungible token is sent in fraction" do
      ledger = %Ledger{
        token: %TokenLedger{
          transfers: [
            %TokenTransfer{
              to: random_address(),
              amount: 123,
              token_address: random_address(),
              token_id: 0
            }
          ]
        }
      }

      tx = TransactionFactory.create_non_valided_transaction(type: :transfer, ledger: ledger)

      assert :ok = PendingTransactionValidation.validate_non_fungible_token_transfer(tx)
    end
  end

  describe "validate_size/1" do
    test "should return :ok when the transaction size is less than 3.1MB" do
      tx =
        TransactionFactory.create_non_valided_transaction(
          type: :data,
          content: :crypto.strong_rand_bytes(3_145_700)
        )

      assert :ok = PendingTransactionValidation.validate_size(tx)
    end

    test "should return transaction data exceeds limit when the transaction size is greater than 3.1MB" do
      tx =
        TransactionFactory.create_non_valided_transaction(
          type: :data,
          content: :crypto.strong_rand_bytes(3_145_728)
        )

      assert {:error, "Transaction data exceeds limit"} =
               PendingTransactionValidation.validate_size(tx)
    end
  end

  describe "validate_previous_public_key" do
    test "should return error if previous transaction address is the same address as the current transaction" do
      {public_key, private_key} = Crypto.derive_keypair("seed", 0)

      tx =
        Transaction.new_with_keys(
          :transfer,
          %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: [
                  %UCOLedger.Transfer{to: ArchethicCase.random_address(), amount: 100_000_000}
                ]
              }
            }
          },
          private_key,
          public_key,
          public_key
        )

      assert {:error, "Invalid previous public key (should be chain index - 1)"} =
               PendingTransactionValidation.validate_previous_public_key(tx)
    end
  end

  describe "validate_ownerships" do
    defp get_tx(ownerships) do
      TransactionFactory.create_non_valided_transaction(type: :data, ownerships: ownerships)
    end

    test "validate conditions for ownerships" do
      assert :ok = PendingTransactionValidation.validate_ownerships(get_tx([]))

      assert {:error, "Ownership: empty secret"} =
               [%Ownership{secret: "", authorized_keys: %{}}]
               |> get_tx()
               |> PendingTransactionValidation.validate_ownerships()

      assert {:error, "Ownership: empty authorized keys"} =
               [%Ownership{secret: random_secret(), authorized_keys: %{}}]
               |> get_tx()
               |> PendingTransactionValidation.validate_ownerships()

      assert {:error, "Ownership: invalid public key"} =
               [%Ownership{secret: random_secret(), authorized_keys: %{"" => "encrypted_key"}}]
               |> get_tx()
               |> PendingTransactionValidation.validate_ownerships()

      assert {:error, "Ownership: invalid public key"} =
               [%Ownership{secret: random_secret(), authorized_keys: %{"abc" => "cba"}}]
               |> get_tx()
               |> PendingTransactionValidation.validate_ownerships()

      assert {:error, "Ownership: invalid encrypted key"} =
               [
                 %Ownership{
                   secret: random_secret(),
                   authorized_keys: %{random_public_key() => :crypto.strong_rand_bytes(10)}
                 }
               ]
               |> get_tx()
               |> PendingTransactionValidation.validate_ownerships()

      pub = random_public_key()

      assert :ok =
               [
                 %Ownership{
                   secret: random_secret(),
                   authorized_keys: %{pub => random_encrypted_key(pub)}
                 }
               ]
               |> get_tx()
               |> PendingTransactionValidation.validate_ownerships()
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
               code
               |> ContractFactory.create_valid_contract_tx()
               |> PendingTransactionValidation.validate_contract()
    end

    test "exceeds max code size" do
      code = generate_code_that_exceed_limit_when_compressed()

      assert {:error, "Invalid transaction, code exceed max size"} =
               code
               |> ContractFactory.create_valid_contract_tx()
               |> PendingTransactionValidation.validate_contract()
    end

    test "invalid bytecode" do
      assert {:error, "Smart contract invalid \"invalid bytecode\""} =
               Transaction.new(
                 :contract,
                 %TransactionData{
                   contract: %Archethic.TransactionChain.TransactionData.Contract{
                     bytecode: "",
                     manifest: %{}
                   }
                 },
                 "seed",
                 0,
                 version: 4
               )
               |> PendingTransactionValidation.validate_contract()
    end

    test "invalid manifest" do
      assert {:error,
              "Smart contract invalid \"invalid manifest - [{\\\"Required property abi was not present.\\\", \\\"#\\\"}]\""} =
               Transaction.new(
                 :contract,
                 %TransactionData{
                   contract: %Archethic.TransactionChain.TransactionData.Contract{
                     bytecode: :zlib.zip(:crypto.strong_rand_bytes(32)),
                     manifest: %{
                       "key" => "value"
                     }
                   }
                 },
                 "seed",
                 0,
                 version: 4
               )
               |> PendingTransactionValidation.validate_contract()
    end

    test "invalid wasm module" do
      assert {:error,
              "Smart contract invalid \"Error while parsing bytes: input bytes aren't valid utf-8.\""} =
               Transaction.new(
                 :contract,
                 %TransactionData{
                   contract: %Archethic.TransactionChain.TransactionData.Contract{
                     bytecode: :zlib.zip(:crypto.strong_rand_bytes(32)),
                     manifest: %{
                       "abi" => %{
                         "functions" => %{},
                         "state" => %{}
                       }
                     }
                   }
                 },
                 "seed",
                 0,
                 version: 4
               )
               |> PendingTransactionValidation.validate_contract()
    end
  end

  describe "Data" do
    test "Should return error when both content and ownerships are empty" do
      assert {:error, "Invalid data type transaction - Both content & ownership are empty"} =
               TransactionFactory.create_non_valided_transaction(type: :data)
               |> PendingTransactionValidation.validate_type_rules(DateTime.utc_now())

      pub = random_public_key()

      assert :ok =
               [
                 %Ownership{
                   secret: random_secret(),
                   authorized_keys: %{pub => random_encrypted_key(pub)}
                 }
               ]
               |> get_tx()
               |> PendingTransactionValidation.validate_type_rules(DateTime.utc_now())

      assert :ok =
               TransactionFactory.create_non_valided_transaction(type: :data, content: "content")
               |> PendingTransactionValidation.validate_type_rules(DateTime.utc_now())
    end
  end

  describe "Code Approval" do
    test "should return :ok when a code approval transaction contains a proposal target and the sender is member of the technical council and not previously signed" do
      tx =
        TransactionFactory.create_non_valided_transaction(
          type: :code_approval,
          recipients: [%Recipient{address: random_address()}]
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

      content = """
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

      proposal_tx =
        TransactionFactory.create_valid_transaction([], content: content, type: :code_proposal)

      MockDB
      |> expect(:get_transaction, fn _, _, _ -> {:ok, proposal_tx} end)

      MockClient
      |> stub(:send_message, fn
        _, %GetFirstPublicKey{}, _ ->
          {:ok, %FirstPublicKey{public_key: tx.previous_public_key}}

        _, %GetTransactionSummary{}, _ ->
          {:ok, %NotFound{}}
      end)

      assert :ok = PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())
    end
  end

  describe "Contract" do
    test "should return error when code  or contract is empty" do
      assert {:error, "Invalid contract type transaction -  contract's code is empty"} =
               ContractFactory.create_valid_contract_tx("")
               |> PendingTransactionValidation.validate_type_rules(DateTime.utc_now())
    end
  end

  describe "Hosting" do
    test "should return :ok when we deploy a aeweb ref transaction" do
      content =
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

      tx = TransactionFactory.create_non_valided_transaction(type: :hosting, content: content)

      assert :ok = PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())
    end

    test "should return :ok when we deploy a aeweb ref transaction with publicationStatus" do
      content =
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

      tx = TransactionFactory.create_non_valided_transaction(type: :hosting, content: content)

      assert :ok = PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())
    end

    test "should return :ok when we deploy a aeweb ref transaction (unpublished)" do
      content =
        Jason.encode!(%{
          "aewebVersion" => 1,
          "publicationStatus" => "UNPUBLISHED"
        })

      tx = TransactionFactory.create_non_valided_transaction(type: :hosting, content: content)

      assert :ok = PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())
    end

    test "should return :ok when we deploy a aeweb file transaction" do
      content =
        Jason.encode!(%{
          "index.html" => Base.url_encode64(:crypto.strong_rand_bytes(1000))
        })

      tx = TransactionFactory.create_non_valided_transaction(type: :hosting, content: content)

      assert :ok = PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())
    end

    test "should return :error when we deploy a wrong aeweb file transaction" do
      content = Jason.encode!(%{"index.html" => 32})

      tx = TransactionFactory.create_non_valided_transaction(type: :hosting, content: content)

      assert {:error, _} =
               PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())
    end

    test "should return :error when we deploy a wrong aeweb ref transaction" do
      content =
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

      tx = TransactionFactory.create_non_valided_transaction(type: :hosting, content: content)

      assert {:error, _} =
               PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())
    end

    test "should return :error when we deploy a wrong aeweb ref transaction (unpublished)" do
      content =
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

      tx = TransactionFactory.create_non_valided_transaction(type: :hosting, content: content)

      assert {:error, _} =
               PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())
    end

    test "should return :error when it does not respect the schema" do
      content =
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

      tx = TransactionFactory.create_non_valided_transaction(type: :hosting, content: content)

      assert {:error, _} =
               PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())
    end
  end

  describe "Node" do
    test "should return :ok when a node transaction data content contains node endpoint information" do
      {origin_public_key, _} =
        Crypto.generate_deterministic_keypair(:crypto.strong_rand_bytes(32), :secp256r1)

      {_, ca_pv} = :crypto.generate_key(:ecdh, :secp256r1, "ca_root_key")
      <<_::8, _::8, origin_key::binary>> = origin_public_key
      certificate = Crypto.ECDSA.sign(:secp256r1, ca_pv, origin_key)

      content =
        Node.encode_transaction_content(
          {80, 20, 10, 200},
          3000,
          4000,
          :tcp,
          <<0, 0, 4, 221, 19, 74, 75, 69, 16, 50, 149, 253, 24, 115, 128, 241, 110, 118, 139, 7,
            48, 217, 58, 43, 145, 233, 77, 125, 190, 207, 31, 64, 157, 137>>,
          origin_public_key,
          certificate,
          Crypto.generate_random_keypair(:bls) |> elem(0)
        )

      tx = TransactionFactory.create_non_valided_transaction(type: :node, content: content)

      MockDB
      |> stub(:get_last_chain_address, fn address ->
        address
      end)

      assert :ok = PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())
    end

    test "should return an error when a node transaction public key used on non allowed origin" do
      Application.put_env(:archethic, Archethic.Mining.PendingTransactionValidation,
        allowed_node_key_origins: [:tpm]
      )

      {public_key, _} = Crypto.derive_keypair("seed", 0)
      certificate = Crypto.get_key_certificate(public_key)

      content =
        Node.encode_transaction_content(
          {80, 20, 10, 200},
          3000,
          4000,
          :tcp,
          <<0, 0, 4, 221, 19, 74, 75, 69, 16, 50, 149, 253, 24, 115, 128, 241, 110, 118, 139, 7,
            48, 217, 58, 43, 145, 233, 77, 125, 190, 207, 31, 64, 157, 137>>,
          <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          certificate,
          Crypto.generate_random_keypair(:bls) |> elem(0)
        )

      tx =
        TransactionFactory.create_non_valided_transaction(
          type: :node,
          content: content,
          seed: "seed"
        )

      MockDB
      |> stub(:get_last_chain_address, fn address ->
        address
      end)

      assert {:error, "Invalid node transaction with invalid key origin"} =
               PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())
    end
  end

  describe "Node Shared Secrets" do
    test "should return :ok when a node shared secrets transaction data keys contains existing node public keys with first tx" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: Crypto.derive_keypair("node_key1", 0) |> elem(0),
        last_public_key: Crypto.derive_keypair("node_key1", 1) |> elem(0),
        available?: true
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: Crypto.derive_keypair("node_key2", 0) |> elem(0),
        last_public_key: Crypto.derive_keypair("node_key2", 1) |> elem(0),
        available?: true
      })

      MockDB
      |> expect(:get_latest_tps, 2, fn -> 1000.0 end)

      content_without_version =
        <<0, 1, 219, 82, 144, 35, 140, 59, 161, 231, 225, 145, 111, 203, 173, 197, 200, 150, 213,
          145, 87, 209, 98, 25, 28, 148, 198, 77, 174, 48, 16, 117, 253, 15, 0, 0, 105, 113, 238,
          128, 201, 90, 172, 230, 46, 99, 215, 130, 104, 26, 196, 222, 157, 89, 101, 74, 248, 245,
          118, 36, 194, 213, 108, 141, 175, 248, 6, 120>>

      content_with_version =
        <<1, 0, 0, 219, 82, 144, 35, 140, 59, 161, 231, 225, 145, 111, 203, 173, 197, 200, 150,
          213, 145, 87, 209, 98, 25, 28, 148, 198, 77, 174, 48, 16, 117, 253, 15>>

      code = """
      condition inherit: [
        type: node_shared_secrets
      ]
      """

      {pub1, _} = Crypto.derive_keypair("node_key1", 0)
      {pub2, _} = Crypto.derive_keypair("node_key2", 0)
      last_pub = Crypto.last_node_public_key()

      ownership = %Ownership{
        secret: random_secret(),
        authorized_keys: %{
          pub1 => random_encrypted_key(pub1),
          pub2 => random_encrypted_key(pub2),
          # we started and connected this node in setup
          last_pub => random_encrypted_key(last_pub)
        }
      }

      tx =
        TransactionFactory.create_non_valided_transaction(
          type: :node_shared_secrets,
          content: content_without_version,
          code: code,
          ownerships: [ownership]
        )

      :persistent_term.put(:node_shared_secrets_gen_addr, Transaction.previous_address(tx))

      assert :ok = PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())
      assert :ok = PendingTransactionValidation.validate_network_chain(tx)

      tx =
        TransactionFactory.create_non_valided_transaction(
          type: :node_shared_secrets,
          content: content_with_version,
          code: code,
          ownerships: [ownership]
        )

      assert :ok = PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())
      assert :ok = PendingTransactionValidation.validate_network_chain(tx)

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

      content =
        <<0, 1, 219, 82, 144, 35, 140, 59, 161, 231, 225, 145, 111, 203, 173, 197, 200, 150, 213,
          145, 87, 209, 98, 25, 28, 148, 198, 77, 174, 48, 16, 117, 253, 15, 0, 0, 105, 113, 238,
          128, 201, 90, 172, 230, 46, 99, 215, 130, 104, 26, 196, 222, 157, 89, 101, 74, 248, 245,
          118, 36, 194, 213, 108, 141, 175, 248, 6, 120>>

      code = """
      condition inherit: [
        type: node_shared_secrets
      ]
      """

      last_pub = Crypto.last_node_public_key()

      ownership = %Ownership{
        secret: random_secret(),
        authorized_keys: %{
          # we started and connected this node in setup
          last_pub => random_encrypted_key(last_pub)
        }
      }

      tx =
        TransactionFactory.create_non_valided_transaction(
          type: :node_shared_secrets,
          content: content,
          code: code,
          ownerships: [ownership]
        )

      :persistent_term.put(:node_shared_secrets_gen_addr, Transaction.previous_address(tx))

      assert {:error, "Invalid node shared secrets transaction authorized nodes"} =
               PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())

      :persistent_term.put(:node_shared_secrets_gen_addr, nil)
    end

    test "should return error when there is already a node shared secrets transaction since the last schedule" do
      MockDB
      |> expect(:get_last_chain_address, fn _, _ ->
        {"OtherAddress", DateTime.utc_now()}
      end)

      pub = random_public_key()

      ownership = %Ownership{
        secret: random_secret(),
        authorized_keys: %{pub => random_encrypted_key(pub)}
      }

      tx =
        TransactionFactory.create_non_valided_transaction(
          type: :node_shared_secrets,
          content: :crypto.strong_rand_bytes(32),
          ownerships: [ownership]
        )

      assert {:error, "Invalid node shared secrets trigger time"} =
               PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())
    end
  end

  describe "Oracle" do
    test "should return error when there is already a oracle transaction since the last schedule" do
      MockDB
      |> expect(:get_last_chain_address, fn _, _ ->
        {"OtherAddress", DateTime.utc_now()}
      end)

      tx = TransactionFactory.create_non_valided_transaction(type: :oracle)

      assert {:error, "Invalid oracle trigger time"} =
               PendingTransactionValidation.validate_type_rules(tx, ~U[2022-01-01 00:10:03Z])
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

      code = """
      condition inherit: [
        type: origin,
        content: true
      ]
      """

      content = <<public_key::binary, certificate_size::16, certificate::binary>>

      tx =
        TransactionFactory.create_non_valided_transaction(
          type: :origin,
          code: code,
          content: content
        )

      :persistent_term.put(:origin_gen_addr, [Transaction.previous_address(tx)])

      assert :ok = PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())

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

      code = """
      condition inherit: [
        type: origin,
        content: true
      ]
      """

      content = <<public_key::binary, certificate_size::16, certificate::binary>>

      tx =
        TransactionFactory.create_non_valided_transaction(
          type: :origin,
          code: code,
          content: content
        )

      :persistent_term.put(:origin_gen_addr, [Transaction.previous_address(tx)])

      assert {:error, "Invalid Origin transaction Public Key Already Exists"} =
               PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())

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

      code = """
      condition inherit: [
        type: origin,
        content: true
      ]
      """

      content = <<public_key::binary, certificate_size::16, certificate::binary>>

      tx =
        TransactionFactory.create_non_valided_transaction(
          type: :origin,
          code: code,
          content: content
        )

      :persistent_term.put(:origin_gen_addr, [Transaction.previous_address(tx)])

      assert :ok = PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())

      :persistent_term.put(:origin_gen_addr, nil)
    end
  end

  describe "Reward" do
    test "should return :ok when a mint reward transaction passes all tests" do
      :persistent_term.put(:archethic_up, nil)

      content =
        Jason.encode!(%{
          supply: 300_000_000,
          name: "MyToken",
          type: "fungible",
          symbol: "MTK"
        })

      tx =
        TransactionFactory.create_non_valided_transaction(type: :mint_rewards, content: content)

      {:ok, pid} = Scheduler.start_link(interval: "0 * * * * *")

      assert {:idle, %{interval: "0 * * * * *"}} = :sys.get_state(pid)

      send(pid, :node_up)

      assert {:scheduled, %{interval: "0 * * * * *"}} = :sys.get_state(pid)

      MockDB
      |> stub(:get_latest_burned_fees, fn -> 300_000_000 end)
      |> stub(:get_last_chain_address, fn _, _ -> {tx.address, DateTime.utc_now()} end)
      |> stub(:get_last_chain_address, fn _ -> {tx.address, DateTime.utc_now()} end)

      :persistent_term.put(:reward_gen_addr, Transaction.previous_address(tx))

      assert :ok = PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())

      :persistent_term.put(:reward_gen_addr, nil)
      :persistent_term.put(:archethic_up, :up)
    end

    test "should return :error when a mint reward transaction has != burned_fees" do
      :persistent_term.put(:archethic_up, nil)

      content =
        Jason.encode!(%{
          supply: 300_000_000,
          name: "MyToken",
          type: "fungible",
          symbol: "MTK"
        })

      tx =
        TransactionFactory.create_non_valided_transaction(type: :mint_rewards, content: content)

      {:ok, pid} = Scheduler.start_link(interval: "0 * * * * *")

      assert {:idle, %{interval: "0 * * * * *"}} = :sys.get_state(pid)

      send(pid, :node_up)

      assert {:scheduled, %{interval: "0 * * * * *"}} = :sys.get_state(pid)

      MockDB
      |> stub(:get_latest_burned_fees, fn -> 200_000_000 end)
      |> stub(:get_last_chain_address, fn _, _ -> {tx.address, DateTime.utc_now()} end)
      |> stub(:get_last_chain_address, fn _ -> {tx.address, DateTime.utc_now()} end)

      assert {:error, "The supply do not match burned fees from last summary"} =
               PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())

      :persistent_term.put(:archethic_up, :up)
    end

    test "should return :error when there is already a mint rewards transaction since last schedule" do
      :persistent_term.put(:archethic_up, nil)

      content =
        Jason.encode!(%{
          supply: 300_000_000,
          name: "MyToken",
          type: "fungible",
          symbol: "MTK"
        })

      tx =
        TransactionFactory.create_non_valided_transaction(type: :mint_rewards, content: content)

      {:ok, pid} = Scheduler.start_link(interval: "0 * * * * *")

      assert {:idle, %{interval: "0 * * * * *"}} = :sys.get_state(pid)

      send(pid, :node_up)

      assert {:scheduled, %{interval: "0 * * * * *"}} = :sys.get_state(pid)

      MockDB
      |> stub(:get_latest_burned_fees, fn -> 300_000_000 end)
      |> stub(:get_last_chain_address, fn _, _ -> {tx.address, DateTime.utc_now()} end)

      assert {:error, "There is already a mint rewards transaction since last schedule"} =
               PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())

      :persistent_term.put(:archethic_up, :up)
    end

    test "should return error when there is already a node rewards transaction since the last schedule" do
      MockDB
      |> expect(:get_last_chain_address, fn _, _ ->
        {"OtherAddress", DateTime.utc_now()}
      end)
      |> expect(:get_transaction, fn _, _, _ ->
        {:ok, %Transaction{type: :node_rewards}}
      end)

      tx = TransactionFactory.create_non_valided_transaction(type: :node_rewards)

      assert {:error, "Invalid node rewards trigger time"} =
               PendingTransactionValidation.validate_type_rules(tx, ~U[2022-01-01 00:00:03Z])
    end
  end

  describe "token" do
    test "should return :ok when a transaction contains valid fields for token creation" do
      content =
        Jason.encode!(%{
          supply: 300_000_000,
          name: "MyToken",
          type: "non-fungible",
          symbol: "MTK",
          decimals: 8,
          properties: %{
            global: "property"
          },
          collection: [
            %{image: "link", value: "link"},
            %{image: "link", value: "link"},
            %{image: "link", value: "link"}
          ]
        })

      tx = TransactionFactory.create_non_valided_transaction(type: :token, content: content)

      assert :ok = PendingTransactionValidation.validate_token_transaction(tx)
    end

    test "should return ok with a token creation with allow_mint flag" do
      content =
        Jason.encode!(%{
          aeip: [2, 18],
          supply: 100_000_000_000,
          name: "CoinCoin",
          type: "fungible",
          symbol: "CC",
          allow_mint: true
        })

      tx = TransactionFactory.create_non_valided_transaction(type: :token, content: content)

      assert :ok = PendingTransactionValidation.validate_token_transaction(tx)
    end

    test "should return ok with a valid token resupply" do
      address = random_address()
      genesis_address = random_address()

      content =
        Jason.encode!(%{
          supply: 100_000_000_000,
          aeip: [2, 18],
          token_reference: address |> Base.encode16()
        })

      tx = TransactionFactory.create_non_valided_transaction(type: :token, content: content)

      content = """
       {
        "supply": 10000000000,
        "type": "fungible",
        "decimals": 7,
        "name": "CoinCoin",
        "allow_mint": true,
        "aeip": [2, 18]
       }
      """

      token_tx = TransactionFactory.create_valid_transaction([], type: :token, content: content)

      with_mock(
        TransactionChain,
        [:passthrough],
        fetch_genesis_address: fn _, _ -> {:ok, genesis_address} end,
        fetch_transaction: fn _, _ -> {:ok, token_tx} end
      ) do
        assert :ok = PendingTransactionValidation.validate_token_transaction(tx)

        assert_called_exactly(TransactionChain.fetch_genesis_address(:_, :_), 2)
      end
    end

    test "should return error if not in the same chain" do
      address = random_address()
      genesis_address = random_address()
      genesis_address2 = random_address()

      content =
        Jason.encode!(%{
          supply: 100_000_000_000,
          aeip: [2, 18],
          token_reference: address |> Base.encode16()
        })

      tx = TransactionFactory.create_non_valided_transaction(type: :token, content: content)

      content = """
       {
        "supply": 10000000000,
        "type": "fungible",
        "decimals": 8,
        "name": "CoinCoin",
        "allow_mint": true,
        "aeip": [2, 18]
       }
      """

      token_tx = TransactionFactory.create_valid_transaction([], type: :token, content: content)

      with_mock(
        TransactionChain,
        [:passthrough],
        fetch_genesis_address: fn
          ^address, _ -> {:ok, genesis_address}
          _, _ -> {:ok, genesis_address2}
        end,
        fetch_transaction: fn _, _ -> {:ok, token_tx} end
      ) do
        assert {:error,
                "Invalid token transaction - token_reference is not in the same transaction chain"} =
                 PendingTransactionValidation.validate_token_transaction(tx)

        assert_called_exactly(TransactionChain.fetch_genesis_address(:_, :_), 2)
      end
    end

    test "should return error if allow_mint is not true" do
      address = random_address()
      genesis_address = random_address()

      content =
        Jason.encode!(%{
          supply: 100_000_000_000,
          aeip: [2, 18],
          token_reference: address |> Base.encode16()
        })

      tx = TransactionFactory.create_non_valided_transaction(type: :token, content: content)

      content = """
       {
        "supply": 10000000000,
        "type": "fungible",
        "decimals": 8,
        "name": "CoinCoin",
        "aeip": [2, 18]
       }
      """

      token_tx = TransactionFactory.create_valid_transaction([], type: :token, content: content)

      with_mock(
        TransactionChain,
        [:passthrough],
        fetch_genesis_address: fn _, _ -> {:ok, genesis_address} end,
        fetch_transaction: fn _, _ -> {:ok, token_tx} end
      ) do
        assert {:error,
                "Invalid token transaction - token_reference does not have allow_mint: true"} =
                 PendingTransactionValidation.validate_token_transaction(tx)

        assert_called_exactly(TransactionChain.fetch_genesis_address(:_, :_), 2)
      end
    end

    test "should return error if token is non-fungible" do
      address = random_address()
      genesis_address = random_address()

      content =
        Jason.encode!(%{
          supply: 100_000_000_000,
          aeip: [2, 18],
          token_reference: address |> Base.encode16()
        })

      tx = TransactionFactory.create_non_valided_transaction(type: :token, content: content)

      content = """
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

      token_tx = TransactionFactory.create_valid_transaction([], type: :token, content: content)

      with_mock(
        TransactionChain,
        [:passthrough],
        fetch_genesis_address: fn _, _ -> {:ok, genesis_address} end,
        fetch_transaction: fn _, _ -> {:ok, token_tx} end
      ) do
        assert {:error, "Invalid token transaction - token_reference must be fungible"} =
                 PendingTransactionValidation.validate_token_transaction(tx)

        assert_called_exactly(TransactionChain.fetch_genesis_address(:_, :_), 2)
      end
    end

    test "should return error if token reference does not exist" do
      address = random_address()
      genesis_address = random_address()

      content =
        Jason.encode!(%{
          supply: 100_000_000_000,
          aeip: [2, 18],
          token_reference: address |> Base.encode16()
        })

      tx = TransactionFactory.create_non_valided_transaction(type: :token, content: content)

      with_mock(
        TransactionChain,
        [:passthrough],
        fetch_genesis_address: fn _, _ -> {:ok, genesis_address} end,
        fetch_transaction: fn _, _ -> {:error, :transaction_not_exists} end
      ) do
        assert {:error, "Invalid token transaction - token_reference not found"} =
                 PendingTransactionValidation.validate_token_transaction(tx)

        assert_called_exactly(TransactionChain.fetch_genesis_address(:_, :_), 2)
      end
    end

    test "should return error if token reference is not a proper token definition" do
      address = random_address()
      genesis_address = random_address()

      content =
        Jason.encode!(%{
          supply: 100_000_000_000,
          aeip: [2, 18],
          token_reference: address |> Base.encode16()
        })

      tx = TransactionFactory.create_non_valided_transaction(type: :token, content: content)

      with_mock(
        TransactionChain,
        [:passthrough],
        fetch_genesis_address: fn _, _ -> {:ok, genesis_address} end,
        fetch_transaction: fn _, _ ->
          {:ok, TransactionFactory.create_valid_transaction([], content: "not a json")}
        end
      ) do
        assert {:error,
                "Invalid token transaction - token_reference exists but does not contain a valid JSON"} =
                 PendingTransactionValidation.validate_token_transaction(tx)

        assert_called_exactly(TransactionChain.fetch_genesis_address(:_, :_), 2)
      end
    end

    test "should return error if token reference is not hexadecimal" do
      content =
        Jason.encode!(%{
          supply: 100_000_000_000,
          aeip: [2, 18],
          token_reference: "invalidtokenref"
        })

      tx = TransactionFactory.create_non_valided_transaction(type: :token, content: content)

      assert {:error, "Invalid token transaction - neither a token creation nor a token resupply"} =
               PendingTransactionValidation.validate_token_transaction(tx)
    end

    test "should return error if token transaction is incorrect" do
      tx =
        TransactionFactory.create_non_valided_transaction(
          type: :token,
          content: Jason.encode!(%{})
        )

      assert {:error, "Invalid token transaction - neither a token creation nor a token resupply"} =
               PendingTransactionValidation.validate_token_transaction(tx)
    end
  end

  describe "transfer" do
    test "should return :ok when a transaction contains a valid smart contract code" do
      ledger = %Ledger{
        uco: %UCOLedger{
          transfers: [
            %UCOTransfer{to: :crypto.strong_rand_bytes(32), amount: 100_000}
          ]
        }
      }

      code = """
      condition inherit: [
        content: "hello"
      ]

      condition transaction: [
        content: ""
      ]

      actions triggered_by: transaction do
        set_content "hello"
      end
      """

      ownerships = [
        Ownership.new(random_secret(), :crypto.strong_rand_bytes(32), [
          Crypto.storage_nonce_public_key()
        ])
      ]

      tx =
        TransactionFactory.create_non_valided_transaction(
          type: :transfer,
          ledger: ledger,
          code: code,
          ownerships: ownerships
        )

      assert :ok = PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())
    end
  end

  describe "Keychain Transaction" do
    test "should reject empty content in keychain transaction" do
      tx = TransactionFactory.create_non_valided_transaction(type: :keychain, content: "")

      assert {:error, "Invalid Keychain transaction"} =
               PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())
    end

    test "Should Reject keychain tx with empty Ownerships list in keychain transaction" do
      tx = TransactionFactory.create_non_valided_transaction(type: :keychain, content: "content")

      assert {:error, "Invalid Keychain transaction"} =
               PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())
    end

    test "Should Reject keychain tx with UCO tranfers" do
      ownerships = [
        Ownership.new(random_secret(), :crypto.strong_rand_bytes(32), [
          Crypto.storage_nonce_public_key()
        ])
      ]

      ledger = %Ledger{
        uco: %UCOLedger{
          transfers: [%UCOTransfer{to: :crypto.strong_rand_bytes(32), amount: 100_000}]
        }
      }

      tx =
        TransactionFactory.create_non_valided_transaction(
          type: :keychain,
          content: "content",
          ledger: ledger,
          ownerships: ownerships
        )

      assert {:error, "Invalid Keychain transaction"} =
               PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())

      ledger = %Ledger{
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

      tx =
        TransactionFactory.create_non_valided_transaction(
          type: :keychain,
          content: "content",
          ledger: ledger,
          ownerships: ownerships
        )

      assert {:error, "Invalid Keychain transaction"} =
               PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())

      ledger = %Ledger{
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

      tx =
        TransactionFactory.create_non_valided_transaction(
          type: :keychain,
          content: "content",
          ledger: ledger,
          ownerships: ownerships
        )

      assert {:error, "Invalid Keychain transaction"} =
               PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())
    end
  end

  describe "Keychain Acesss Transaction" do
    test "should reject invalid transaction" do
      ownerships = [
        Ownership.new(random_secret(), :crypto.strong_rand_bytes(32), [
          Crypto.storage_nonce_public_key()
        ]),
        Ownership.new(random_secret(), :crypto.strong_rand_bytes(32), [
          Crypto.storage_nonce_public_key()
        ])
      ]

      tx =
        TransactionFactory.create_non_valided_transaction(
          type: :keychain_access,
          ownerships: ownerships
        )

      assert {:error, "Invalid Keychain Access transaction"} =
               PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())

      tx = TransactionFactory.create_non_valided_transaction(type: :keychain_access)

      assert {:error, "Invalid Keychain Access transaction"} =
               PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())

      ownerships = [
        Ownership.new(random_secret(), :crypto.strong_rand_bytes(32), [
          Crypto.storage_nonce_public_key()
        ])
      ]

      tx =
        TransactionFactory.create_non_valided_transaction(
          type: :keychain_access,
          content: "content",
          ownerships: ownerships
        )

      assert {:error, "Invalid Keychain Access transaction"} =
               PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())

      tx =
        TransactionFactory.create_non_valided_transaction(
          type: :keychain_access,
          content: "",
          ownerships: ownerships
        )

      assert {:error,
              "Invalid Keychain access transaction - Previous public key must be authorized"} =
               PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())

      tx =
        TransactionFactory.create_non_valided_transaction(
          type: :keychain_access,
          content: "",
          ownerships: ownerships,
          recipients: [%Recipient{address: random_address()}]
        )

      assert {:error, "Invalid Keychain Access transaction"} =
               PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())

      tx =
        TransactionFactory.create_non_valided_transaction(
          type: :keychain_access,
          content: "",
          ownerships: ownerships,
          recipients: [%Recipient{address: random_address(), action: "do_something", args: %{}}]
        )

      assert {:error, "Invalid Keychain Access transaction"} =
               PendingTransactionValidation.validate_type_rules(tx, DateTime.utc_now())
    end
  end
end
