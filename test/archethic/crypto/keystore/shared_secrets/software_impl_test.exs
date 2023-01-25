defmodule Archethic.Crypto.SharedSecrets.SoftwareImplTest do
  use ArchethicCase

  alias Archethic.Crypto
  alias Archethic.Crypto.SharedSecretsKeystore.SoftwareImpl, as: Keystore

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ownership

  import Mox

  setup :set_mox_global

  describe "start_link/1" do
    test "should initialize the node shared secrets to null when not transaction found" do
      {:ok, _pid} = Keystore.start_link()
      assert [{_, 0}] = :ets.lookup(:archethic_shared_secrets_keystore, :shared_secrets_index)
      assert [{_, 0}] = :ets.lookup(:archethic_shared_secrets_keystore, :network_pool_index)
    end

    test "should initialize the node shared secrets index from the stored transactions" do
      %{secrets: secrets, daily_nonce_seed: daily_nonce_seed, aes_key: aes_key} = gen_secrets()

      timestamp = ~U[2021-10-09 23:55:00Z]

      MockDB
      |> stub(:count_transactions_by_type, fn
        :node_rewards -> 1
        :node_shared_secrets -> 1
        :mint_rewards -> 1
      end)
      |> expect(:list_addresses_by_type, fn :node_shared_secrets ->
        [:crypto.strong_rand_bytes(32)]
      end)
      |> expect(:get_transaction, fn _, _, _ ->
        {:ok,
         %Transaction{
           data: %TransactionData{
             ownerships: [Ownership.new(secrets, aes_key, [Crypto.last_node_public_key()])]
           },
           validation_stamp: %ValidationStamp{
             timestamp: timestamp
           }
         }}
      end)

      {:ok, _pid} = Keystore.start_link()

      daily_nonce_keypair = Crypto.generate_deterministic_keypair(daily_nonce_seed)

      unix_timestamp = DateTime.to_unix(~U[2021-10-10 00:00:00Z])

      assert [{_, 1}] = :ets.lookup(:archethic_shared_secrets_keystore, :shared_secrets_index)
      assert [{_, 2}] = :ets.lookup(:archethic_shared_secrets_keystore, :network_pool_index)

      assert [{^unix_timestamp, sign_fun}] = :ets.tab2list(:archethic_shared_secrets_daily_keys)
      assert sign_fun.("hello") == Crypto.sign("hello", elem(daily_nonce_keypair, 1))
    end
  end

  test "unwrap_secrets/3 should load encrypted secrets by decrypting them" do
    {:ok, _pid} = Keystore.start_link()

    timestamp = ~U[2021-04-08 06:35:17Z]

    {daily_nonce_seed, transaction_seed, network_pool_seed} =
      load_secrets(~U[2021-04-08 06:35:17Z])

    unix_timestamp = DateTime.to_unix(timestamp)

    assert [{^unix_timestamp, sign_fun}] = :ets.tab2list(:archethic_shared_secrets_daily_keys)
    [{_, tx_sign_fun}] = :ets.lookup(:archethic_shared_secrets_keystore, :transaction_sign_fun)

    [{_, network_pool_sign_fun}] =
      :ets.lookup(:archethic_shared_secrets_keystore, :network_pool_sign_fun)

    {_, pv} = Crypto.generate_deterministic_keypair(daily_nonce_seed)
    assert sign_fun.("hello") == Crypto.sign("hello", pv)

    {_, pv} = Crypto.derive_keypair(transaction_seed, 0)
    assert tx_sign_fun.("hello", 0) == Crypto.sign("hello", pv)

    {_, pv} = Crypto.derive_keypair(network_pool_seed, 0)
    assert network_pool_sign_fun.("hello", 0) == Crypto.sign("hello", pv)
  end

  test "sign_with_node_shared_secrets_key/1 should sign the data with the latest node shared secrets private key" do
    Keystore.start_link()

    {_, transaction_seed, _} = load_secrets(~U[2021-04-08 06:35:17Z])
    {_, pv} = Crypto.derive_keypair(transaction_seed, 0)

    assert Crypto.sign("hello", pv) == Keystore.sign_with_node_shared_secrets_key("hello")
  end

  test "sign_with_node_shared_secrets_key/2 should sign the data with a given node shared secrets private key" do
    Keystore.start_link()

    {_, transaction_seed, _} = load_secrets(~U[2021-04-08 06:35:17Z])
    {_, pv} = Crypto.derive_keypair(transaction_seed, 2)

    assert Crypto.sign("hello", pv) ==
             Keystore.sign_with_node_shared_secrets_key("hello", 2)
  end

  test "node_shared_secrets_public_key/1 should return a given node shared secrets public key" do
    Keystore.start_link()

    {_, transaction_seed, _} = load_secrets(~U[2021-04-08 06:35:17Z])
    {pub, _} = Crypto.derive_keypair(transaction_seed, 2)

    assert pub == Keystore.node_shared_secrets_public_key(2)
  end

  test "sign_with_network_pool_key/1 should sign the data with the latest network pool private key" do
    Keystore.start_link()

    {_, _, network_pool_seed} = load_secrets(~U[2021-04-08 06:35:17Z])
    {_, pv} = Crypto.derive_keypair(network_pool_seed, 0)

    assert Crypto.sign("hello", pv) == Keystore.sign_with_network_pool_key("hello")
  end

  test "sign_with_network_pool_key/2 should sign the data with a given network pool private key" do
    Keystore.start_link()

    {_, _, network_pool_seed} = load_secrets(~U[2021-04-08 06:35:17Z])
    {_, pv} = Crypto.derive_keypair(network_pool_seed, 2)

    assert Crypto.sign("hello", pv) == Keystore.sign_with_network_pool_key("hello", 2)
  end

  test "network_pool_public_key/1 should return a given network pool public key" do
    Keystore.start_link()

    {_, _, network_pool_seed} = load_secrets(~U[2021-04-08 06:35:17Z])
    {pub, _} = Crypto.derive_keypair(network_pool_seed, 2)

    assert pub == Keystore.network_pool_public_key(2)
  end

  test ":archethic_shared_secrets_daily_keys should keep only 2 most recent elements" do
    Keystore.start_link()

    timestamp_1 = ~U[2021-04-08 06:35:17Z]
    timestamp_2 = ~U[2021-04-08 06:36:17Z]
    timestamp_3 = ~U[2021-04-08 06:37:17Z]

    load_secrets(timestamp_1)
    load_secrets(timestamp_2)
    load_secrets(timestamp_3)

    unix_timestamp_2 = DateTime.to_unix(timestamp_2)
    unix_timestamp_3 = DateTime.to_unix(timestamp_3)

    assert [{^unix_timestamp_2, _}, {^unix_timestamp_3, _}] =
             :ets.tab2list(:archethic_shared_secrets_daily_keys)
  end

  defp load_secrets(timestamp = %DateTime{}) do
    public_key = Crypto.last_node_public_key()

    %{
      secrets: secrets,
      daily_nonce_seed: daily_nonce_seed,
      transaction_seed: transaction_seed,
      network_pool_seed: network_pool_seed,
      aes_key: aes_key
    } = gen_secrets()

    encrypted_key = Crypto.ec_encrypt(aes_key, public_key)

    assert :ok = Keystore.unwrap_secrets(secrets, encrypted_key, timestamp)

    {daily_nonce_seed, transaction_seed, network_pool_seed}
  end

  defp gen_secrets do
    aes_key = :crypto.strong_rand_bytes(32)

    daily_nonce_seed = :crypto.strong_rand_bytes(32)
    transaction_seed = :crypto.strong_rand_bytes(32)
    network_pool_seed = :crypto.strong_rand_bytes(32)

    encrypted_daily_nonce_seed = Crypto.aes_encrypt(daily_nonce_seed, aes_key)
    encrypted_transaction_seed = Crypto.aes_encrypt(transaction_seed, aes_key)
    encrypted_network_pool_seed = Crypto.aes_encrypt(network_pool_seed, aes_key)

    secrets =
      <<encrypted_daily_nonce_seed::binary, encrypted_transaction_seed::binary,
        encrypted_network_pool_seed::binary>>

    %{
      secrets: secrets,
      daily_nonce_seed: daily_nonce_seed,
      transaction_seed: transaction_seed,
      network_pool_seed: network_pool_seed,
      aes_key: aes_key
    }
  end
end
