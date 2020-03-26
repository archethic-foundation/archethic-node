defmodule UnirisSync.BootstrapTest do
  use ExUnit.Case

  import Mox

  alias UnirisP2P.Node
  alias UnirisSync.Bootstrap
  alias UnirisCrypto, as: Crypto
  alias UnirisChain.Transaction

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    me = self()

    MockP2P
    |> stub(:list_seeds, fn ->
      [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          last_public_key: "00CD747D4CB84C07B1E26F241EA1105579CBF94F543658995C9E694B55F919E120",
          first_public_key: "00CD747D4CB84C07B1E26F241EA1105579CBF94F543658995C9E694B55F919E120"
        }
      ]
    end)
    |> stub(:update_seeds, fn _ ->
      send(me, :updated_seeds)
      :ok
    end)
    |> stub(:send_message, fn _, msg ->
      case msg do
        [:new_seeds, {:closest_nodes, _}, {:bootstrap_crypto_seeds, pub}] ->
          [
            [
              %Node{
                ip: {200, 40, 30, 50},
                port: 3000,
                last_public_key:
                  "00B062E1F7C6362C6F621ED93420122AA5AB21C8653FF04C73EB6F77CC68AEAF73",
                first_public_key:
                  "00B062E1F7C6362C6F621ED93420122AA5AB21C8653FF04C73EB6F77CC68AEAF73"
              }
            ],
            [
              %Node{
                ip: {80, 10, 252, 47},
                port: 3000,
                last_public_key:
                  "0059372A63A9A4BE6D00F3673F5D497B5D10A93C69125DAEF309E85E40D74CA0BF",
                first_public_key:
                  "0059372A63A9A4BE6D00F3673F5D497B5D10A93C69125DAEF309E85E40D74CA0BF"
              }
            ],
            %{
              origin_keys_seeds: Crypto.ec_encrypt(["origin_seed"], pub),
              storage_nonce_seed: Crypto.ec_encrypt("storage_nonce_seed", pub)
            }
          ]

        {:new_transaction, %Transaction{type: :node}} ->
          send(me, :acknowledge_storage_node_tx)
          :ok
      end
    end)
    |> stub(:add_node, fn _ ->
      :ok
    end)
    |> stub(:connect_node, fn _ ->
      :ok
    end)
    |> stub(:node_info, fn _ ->
      {:ok,
       %Node{
         ip: {127, 0, 0, 1},
         port: 3000,
         first_public_key: "",
         last_public_key: ""
       }}
    end)
    |> stub(:list_nodes, fn  ->
      [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: "",
          last_public_key: ""
        }
      ]
    end)

    MockSharedSecrets
    |> stub(:new_shared_secrets_transaction, fn seed, _ ->
      aes_key = :crypto.strong_rand_bytes(32)

      Transaction.from_seed(seed, :node_shared_secrets, %Transaction.Data{
        keys: %{
          secret:
            Crypto.aes_encrypt(
              %{
                daily_nonce_seed: :crypto.strong_rand_bytes(32),
                storage_nonce_seed: :crypto.strong_rand_bytes(32),
                origin_keys_seeds: [:crypto.strong_rand_bytes(32)]
              },
              aes_key
            ),
          authorized_keys:
            %{}
            |> Map.put(
              Crypto.node_public_key(),
              Crypto.ec_encrypt(aes_key, Crypto.node_public_key())
            )
        }
      })
    end)
    |> stub(:add_origin_public_key, fn _, _ -> :ok end)

    MockChain
    |> stub(:list_transactions, fn -> [] end)
    |> stub(:get_last_node_shared_secrets_transaction, fn ->
      {:ok, %Transaction{
        address: "",
        type: :node_shared_secrets,
        timestamp: 100510510,
        data: %{},
        previous_public_key: "",
        previous_signature: "",
        origin_signature: ""
      }}
    end)

    MockValidation
    |> stub(:get_proof_of_work, fn _ -> {:ok, ""} end)
    |> stub(:get_proof_of_integrity, fn _ -> "" end)
    |> stub(:get_transaction_fee, fn _ -> 0 end)
    |> stub(:get_node_rewards, fn _, _, _, _, _ -> [] end)
    |> stub(:get_cross_validation_stamp, fn _, _ -> {"", [], ""} end)

    UnirisCrypto.add_origin_seed("seed")

    :ok
  end

  test "run/2 initialize a node by retrieving initializing data, update the new sees and setup the chain" do
    Bootstrap.run({127, 0, 0, 1}, 5000)
    assert_receive :acknowledge_storage_node_tx

  end

  test "run/2 initialize network" do

    me = self()
    MockChain
    |> stub(:get_last_node_shared_secrets_transaction, fn -> {:error, :transaction_not_exists} end)
    |> stub(:store_transaction_chain, fn [%Transaction{type: tx_type} | _] ->
      case tx_type do
        :node ->
          send(me, :acknowledge_storage_node_tx)
          :ok
        :node_shared_secrets ->
            send(me, :acknowledge_storage_shared_secrets_tx)
            :ok
      end
    end)

    MockP2P
    |> stub(:list_seeds, fn ->
      [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: Crypto.node_public_key(),
          last_public_key: Crypto.node_public_key()
        }
      ]
    end)

    Bootstrap.run({127, 0, 0, 1}, 5000)

    assert_receive :acknowledge_storage_shared_secrets_tx
    assert_receive :acknowledge_storage_node_tx

  end
end
