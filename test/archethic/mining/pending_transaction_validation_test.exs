defmodule ArchEthic.Mining.PendingTransactionValidationTest do
  use ArchEthicCase, async: false

  alias ArchEthic.Crypto

  alias ArchEthic.Governance.Pools.MemTable, as: PoolsMemTable

  alias ArchEthic.Mining.PendingTransactionValidation

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.FirstPublicKey
  alias ArchEthic.P2P.Message.GetFirstPublicKey
  alias ArchEthic.P2P.Node

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ownership

  import Mox

  setup do
    P2P.add_and_connect_node(%Node{
      first_public_key: Crypto.last_node_public_key(),
      network_patch: "AAA"
    })

    :ok
  end

  describe "validate_pending_transaction/1" do
    test "should :ok when a node transaction data content contains node endpoint information" do
      {public_key, _} = Crypto.derive_keypair("seed", 0)
      certificate = Crypto.get_key_certificate(public_key)

      tx =
        Transaction.new(
          :node,
          %TransactionData{
            content:
              <<127, 0, 0, 1, 3000::16, 1, 0, 4, 221, 19, 74, 75, 69, 16, 50, 149, 253, 24, 115,
                128, 241, 110, 118, 139, 7, 48, 217, 58, 43, 145, 233, 77, 125, 190, 207, 31, 64,
                157, 137, byte_size(certificate)::16, certificate::binary>>
          },
          "seed",
          0
        )

      assert :ok = PendingTransactionValidation.validate(tx)
    end

    test "should return :ok when a node shared secrets transaction data keys contains existing node public keys with first tx" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "node_key1",
        last_public_key: "node_key1",
        available?: true
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "node_key2",
        last_public_key: "node_key2",
        available?: true
      })

      tx =
        Transaction.new(
          :node_shared_secrets,
          %TransactionData{
            content:
              <<0, 0, 219, 82, 144, 35, 140, 59, 161, 231, 225, 145, 111, 203, 173, 197, 200, 150,
                213, 145, 87, 209, 98, 25, 28, 148, 198, 77, 174, 48, 16, 117, 253, 15, 0, 105,
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
                  "node_key1" => "",
                  "node_key2" => ""
                }
              }
            ]
          }
        )

      assert :ok = PendingTransactionValidation.validate(tx)
    end

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
      |> expect(:get_transaction, fn _, _ ->
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
             @@ -4,7 +4,7 @@ defmodule ArchEthic.MixProject do
               def project do
                 [
                   app: :archethic,
             -      version: \"0.7.1\",
             +      version: \"0.7.2\",
                   build_path: \"_build\",
                   config_path: \"config/config.exs\",
                   deps_path: \"deps\",
             @@ -53,7 +53,7 @@ defmodule ArchEthic.MixProject do
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
      |> expect(:send_message, fn _, %GetFirstPublicKey{} ->
        {:ok, %FirstPublicKey{public_key: tx.previous_public_key}}
      end)

      assert :ok = PendingTransactionValidation.validate(tx)
    end

    test "should return :ok when a transaction contains a valid smart contract code" do
      tx_seed = :crypto.strong_rand_bytes(32)

      tx =
        Transaction.new(
          :transfer,
          %TransactionData{
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
end
