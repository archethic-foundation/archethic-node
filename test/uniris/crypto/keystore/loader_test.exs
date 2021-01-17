defmodule Uniris.Crypto.KeystoreLoaderTest do
  use ExUnit.Case

  alias Uniris.Crypto
  alias Uniris.Crypto.KeystoreLoader

  alias Uniris.TransactionChain.MemTables.ChainLookup
  alias Uniris.TransactionChain.MemTables.KOLedger
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Keys

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    start_supervised!(ChainLookup)
    start_supervised!(KOLedger)

    me = self()

    MockCrypto
    |> stub(:child_spec, fn _ -> {:ok, self()} end)
    |> stub(:number_of_node_shared_secrets_keys, fn -> 0 end)
    |> stub(:number_of_node_keys, fn -> 0 end)
    |> stub(:increment_number_of_generate_node_keys, fn ->
      send(me, :inc_node_keys)
      :ok
    end)
    |> stub(:increment_number_of_generate_node_shared_secrets_keys, fn ->
      send(me, :inc_shared_secrets_keys)
      :ok
    end)

    :ok
  end

  describe "load_transaction/1" do
    test "should increment the number of node shared secrets keys" do
      MockCrypto
      |> expect(:node_public_key, fn -> "Node0" end)

      tx = %Transaction{
        type: :node_shared_secrets,
        data: %TransactionData{keys: %Keys{secret: ""}}
      }

      assert :ok = KeystoreLoader.load_transaction(tx)
      assert_receive :inc_shared_secrets_keys
    end

    test "should decrypt and load node shared secrets seeds" do
      {pub, _} = Crypto.derive_keypair("myseed", 0)

      transaction_seed = :crypto.strong_rand_bytes(32)
      daily_nonce_seed = :crypto.strong_rand_bytes(32)
      secret_key = :crypto.strong_rand_bytes(32)
      encrypted_key = Crypto.ec_encrypt(secret_key, pub)

      me = self()

      MockCrypto
      |> stub(:node_public_key, fn -> pub end)
      |> expect(:encrypt_node_shared_secrets_transaction_seed, fn key ->
        Crypto.aes_encrypt(transaction_seed, key)
      end)
      |> stub(:decrypt_and_set_node_shared_secrets_transaction_seed, fn _, _ ->
        send(me, {:transaction_seed, transaction_seed})
        :ok
      end)
      |> expect(:decrypt_and_set_daily_nonce_seed, fn _, _ ->
        send(me, {:daily_nonce_seed, daily_nonce_seed})
      end)

      transaction_seed
      |> Crypto.aes_encrypt(secret_key)
      |> Crypto.decrypt_and_set_node_shared_secrets_transaction_seed(encrypted_key)

      secret =
        Crypto.aes_encrypt(daily_nonce_seed, secret_key) <>
          Crypto.encrypt_node_shared_secrets_transaction_seed(secret_key)

      tx_keys = Keys.new([pub], secret_key, secret)

      tx = %Transaction{
        type: :node_shared_secrets,
        data: %TransactionData{keys: tx_keys}
      }

      assert :ok = KeystoreLoader.load_transaction(tx)

      assert_receive {:transaction_seed, ^transaction_seed}
      assert_receive {:daily_nonce_seed, ^daily_nonce_seed}
    end

    test "should increment the number of node keys" do
      ChainLookup.reverse_link(Crypto.hash("Node1"), "Node")

      MockCrypto
      |> expect(:node_public_key, fn 0 -> "Node0" end)

      tx = %Transaction{type: :node, previous_public_key: "Node0"}

      assert :ok = KeystoreLoader.load_transaction(tx)
      assert_receive :inc_node_keys
    end

    test "should not increment the number of node keys" do
      ChainLookup.reverse_link(Crypto.hash("Node1"), "Node")

      MockCrypto
      |> expect(:node_public_key, fn 0 -> "Node0" end)

      tx = %Transaction{type: :node, previous_public_key: "Node29"}

      assert :ok = KeystoreLoader.load_transaction(tx)
      refute_receive :inc_node_keys
    end
  end

  describe "start_link/1" do
    test "should load from the database the number of transactions to load" do
      MockCrypto
      |> expect(:node_public_key, fn 0 -> "Node0" end)
      |> expect(:node_public_key, fn -> "Node1" end)

      MockDB
      |> stub(:get_transaction, fn address, _ ->
        cond do
          address == Crypto.hash("Node2") ->
            {:ok,
             %Transaction{
               address: Crypto.hash("Node2"),
               type: :node,
               previous_public_key: "Node1"
             }}

          address == Crypto.hash("Node1") ->
            {:ok,
             %Transaction{
               address: Crypto.hash("Node1"),
               type: :node,
               previous_public_key: "Node0"
             }}

          address == "@NodeSharedSecrets1" ->
            {:ok,
             %Transaction{
               address: "@NodeSharedSecrets1",
               type: :node_shared_secrets,
               data: %TransactionData{keys: %Keys{secret: :crypto.strong_rand_bytes(120)}}
             }}
        end
      end)

      ChainLookup.reverse_link(Crypto.hash("Node2"), "Node1")
      ChainLookup.reverse_link(Crypto.hash("Node1"), "Node0")

      ChainLookup.add_transaction_by_type(
        "@NodeSharedSecrets1",
        :node_shared_secrets,
        DateTime.utc_now()
      )

      assert {:ok, _} = KeystoreLoader.start_link()

      assert_received :inc_node_keys
      assert_received :inc_node_keys

      assert_received :inc_shared_secrets_keys
    end
  end
end
