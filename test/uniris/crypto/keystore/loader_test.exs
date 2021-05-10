defmodule Uniris.Crypto.KeystoreLoaderTest do
  use UnirisCase

  alias Uniris.Crypto
  alias Uniris.Crypto.KeystoreCounter
  alias Uniris.Crypto.KeystoreLoader

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Keys

  import Mox

  describe "load_transaction/1" do
    test "should set the number of node shared secrets keys" do
      MockCrypto
      |> expect(:node_public_key, fn -> "Node0" end)

      tx = %Transaction{
        address: :crypto.strong_rand_bytes(32),
        type: :node_shared_secrets,
        data: %TransactionData{keys: %Keys{secret: ""}},
        validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
      }

      MockDB
      |> expect(:chain_size, fn _ -> 1 end)

      assert :ok = KeystoreLoader.load_transaction(tx)
      assert 1 == KeystoreCounter.get_node_shared_key_counter()
    end

    test "should decrypt and load node shared secrets seeds" do
      {pub, _} = Crypto.derive_keypair("myseed", 0)

      transaction_seed = :crypto.strong_rand_bytes(32)
      daily_nonce_seed = :crypto.strong_rand_bytes(32)
      network_seed = :crypto.strong_rand_bytes(32)

      secret_key = :crypto.strong_rand_bytes(32)
      encrypted_key = Crypto.ec_encrypt(secret_key, pub)

      me = self()

      MockCrypto
      |> stub(:node_public_key, fn -> pub end)
      |> expect(:encrypt_node_shared_secrets_transaction_seed, fn key ->
        Crypto.aes_encrypt(transaction_seed, key)
      end)
      |> expect(:encrypt_network_pool_seed, fn key ->
        Crypto.aes_encrypt(network_seed, key)
      end)
      |> stub(:decrypt_and_set_node_shared_secrets_transaction_seed, fn _, _ ->
        send(me, {:transaction_seed, transaction_seed})
        :ok
      end)
      |> expect(:decrypt_and_set_daily_nonce_seed, fn _, _, _ ->
        send(me, {:daily_nonce_seed, daily_nonce_seed})
        :ok
      end)
      |> expect(:decrypt_and_set_node_shared_secrets_network_pool_seed, fn _, _ ->
        send(me, {:network_seed, network_seed})
        :ok
      end)

      transaction_seed
      |> Crypto.aes_encrypt(secret_key)
      |> Crypto.decrypt_and_set_node_shared_secrets_transaction_seed(encrypted_key)

      secret =
        Crypto.aes_encrypt(daily_nonce_seed, secret_key) <>
          Crypto.encrypt_node_shared_secrets_transaction_seed(secret_key) <>
          Crypto.encrypt_network_pool_seed(secret_key)

      tx_keys = Keys.new([pub], secret_key, secret)

      MockDB
      |> expect(:chain_size, fn _ -> 0 end)

      tx = %Transaction{
        address: :crypto.strong_rand_bytes(32),
        type: :node_shared_secrets,
        data: %TransactionData{keys: tx_keys},
        validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
      }

      assert :ok = KeystoreLoader.load_transaction(tx)

      assert_receive {:transaction_seed, ^transaction_seed}
      assert_receive {:daily_nonce_seed, ^daily_nonce_seed}
      assert_receive {:network_seed, ^network_seed}
    end

    test "should increment the number of node keys" do
      MockCrypto
      |> expect(:node_public_key, fn 0 -> "Node0" end)

      MockDB
      |> expect(:chain_size, fn _ -> 1 end)

      tx = %Transaction{address: Crypto.hash("Node1"), type: :node, previous_public_key: "Node0"}

      assert :ok = KeystoreLoader.load_transaction(tx)
      assert 1 == KeystoreCounter.get_node_key_counter()
    end

    test "should not set the number of node keys" do
      MockCrypto
      |> expect(:node_public_key, fn 0 -> "Node0" end)

      tx = %Transaction{
        type: :node,
        address: Crypto.hash("Node30"),
        previous_public_key: "Node29"
      }

      assert :ok = KeystoreLoader.load_transaction(tx)
      assert 0 == KeystoreCounter.get_node_key_counter()
    end
  end

  describe "start_link/1" do
    test "should load from the database the number of transactions to load" do
      MockCrypto
      |> expect(:node_public_key, fn 0 -> "Node0" end)
      |> expect(:node_public_key, fn -> "Node1" end)

      MockDB
      |> expect(:get_last_chain_address, fn addr ->
        if Crypto.hash("Node0") == addr do
          Crypto.hash("Node2")
        else
          addr
        end
      end)
      |> stub(:chain_size, fn address ->
        cond do
          address == Crypto.hash("Node2") ->
            2

          address == "@NodeSharedSecrets1" ->
            1

          true ->
            0
        end
      end)
      |> stub(:count_transactions_by_type, fn _ -> 0 end)
      |> stub(:list_transactions_by_type, fn
        :node_shared_secrets, _ ->
          [
            %Transaction{
              address: "@NodeSharedSecrets1",
              type: :node_shared_secrets,
              data: %TransactionData{keys: %Keys{secret: :crypto.strong_rand_bytes(120)}},
              validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
            }
          ]

        :node, _ ->
          [
            %Transaction{
              address: Crypto.hash("Node2"),
              type: :node,
              previous_public_key: "Node1",
              validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
            },
            %Transaction{
              address: Crypto.hash("Node1"),
              type: :node,
              previous_public_key: "Node0",
              validation_stamp: %ValidationStamp{
                timestamp: DateTime.utc_now() |> DateTime.add(-60)
              }
            }
          ]
      end)

      assert {:ok, _} = KeystoreLoader.start_link()

      assert 2 == KeystoreCounter.get_node_key_counter()
      assert 1 == KeystoreCounter.get_node_shared_key_counter()
    end
  end
end
