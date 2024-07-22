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
      assert [{_, 0}] = :ets.lookup(:archethic_shared_secrets_keystore, :reward_index)
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

      assert 1 == Keystore.get_node_shared_key_index()
      assert 2 == Keystore.get_reward_key_index()

      assert Keystore.sign_with_daily_nonce_key("hello", ~U[2021-10-10 00:00:00Z]) ==
               Crypto.sign("hello", elem(daily_nonce_keypair, 1))
    end
  end

  test "unwrap_secrets/3 should load encrypted secrets by decrypting them" do
    {:ok, _pid} = Keystore.start_link()
    {_daily_nonce_seed, transaction_seed, reward_seed} = load_secrets(~U[2021-04-08 06:35:17Z])

    assert transaction_seed |> Crypto.derive_keypair(0) |> elem(0) ==
             Keystore.node_shared_secrets_public_key(0)

    assert reward_seed |> Crypto.derive_keypair(0) |> elem(0) == Keystore.reward_public_key(0)
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

  test "sign_with_reward_key/1 should sign the data with the latest network pool private key" do
    Keystore.start_link()

    {_, _, reward_seed} = load_secrets(~U[2021-04-08 06:35:17Z])
    {_, pv} = Crypto.derive_keypair(reward_seed, 0)

    assert Crypto.sign("hello", pv) == Keystore.sign_with_reward_key("hello")
  end

  test "sign_with_reward_key/2 should sign the data with a given network pool private key" do
    Keystore.start_link()

    {_, _, reward_seed} = load_secrets(~U[2021-04-08 06:35:17Z])
    {_, pv} = Crypto.derive_keypair(reward_seed, 2)

    assert Crypto.sign("hello", pv) == Keystore.sign_with_reward_key("hello", 2)
  end

  test "reward_public_key/1 should return a given network pool public key" do
    Keystore.start_link()

    {_, _, reward_seed} = load_secrets(~U[2021-04-08 06:35:17Z])
    {pub, _} = Crypto.derive_keypair(reward_seed, 2)

    assert pub == Keystore.reward_public_key(2)
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
      reward_seed: reward_seed,
      aes_key: aes_key
    } = gen_secrets()

    encrypted_key = Crypto.ec_encrypt(aes_key, public_key)

    assert :ok = Keystore.unwrap_secrets(secrets, encrypted_key, timestamp)

    {daily_nonce_seed, transaction_seed, reward_seed}
  end

  defp gen_secrets do
    aes_key = :crypto.strong_rand_bytes(32)

    daily_nonce_seed = :crypto.strong_rand_bytes(32)
    transaction_seed = :crypto.strong_rand_bytes(32)
    reward_seed = :crypto.strong_rand_bytes(32)

    encrypted_daily_nonce_seed = Crypto.aes_encrypt(daily_nonce_seed, aes_key)
    encrypted_transaction_seed = Crypto.aes_encrypt(transaction_seed, aes_key)
    encrypted_reward_seed = Crypto.aes_encrypt(reward_seed, aes_key)

    secrets =
      <<encrypted_daily_nonce_seed::binary, encrypted_transaction_seed::binary,
        encrypted_reward_seed::binary>>

    %{
      secrets: secrets,
      daily_nonce_seed: daily_nonce_seed,
      transaction_seed: transaction_seed,
      reward_seed: reward_seed,
      aes_key: aes_key
    }
  end
end
