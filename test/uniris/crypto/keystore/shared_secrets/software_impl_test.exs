defmodule Uniris.Crypto.SharedSecrets.SoftwareImplTest do
  use UnirisCase

  alias Uniris.Crypto
  alias Uniris.Crypto.SharedSecretsKeystore.SoftwareImpl, as: Keystore

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Keys

  import Mox

  setup :set_mox_global

  describe "start_link/1" do
    test "should initialize the node shared secrets to null when not transaction found" do
      {:ok, pid} = Keystore.start_link()

      assert {:idle, %{daily_nonce_keys: %{}, shared_secrets_index: 0, network_pool_index: 0}} =
               :sys.get_state(pid)
    end

    test "should initialize the node shared secrets index from the stored transactions" do
      %{secrets: secrets, daily_nonce_seed: daily_nonce_seed, aes_key: aes_key} = gen_secrets()

      timestamp = ~U[2021-10-10 00:00:00Z]

      MockDB
      |> expect(:count_transactions_by_type, fn
        :node_rewards -> 1
      end)
      |> expect(:list_transactions_by_type, fn :node_shared_secrets, _ ->
        [
          %Transaction{
            data: %TransactionData{
              keys: Keys.new([Crypto.last_node_public_key()], aes_key, secrets)
            },
            validation_stamp: %ValidationStamp{
              timestamp: timestamp
            }
          }
        ]
      end)

      {:ok, pid} = Keystore.start_link()

      daily_nonce_keypair = Crypto.generate_deterministic_keypair(daily_nonce_seed)

      assert {:authorized,
              %{
                daily_nonce_keys: %{^timestamp => ^daily_nonce_keypair},
                shared_secrets_index: 1,
                network_pool_index: 1
              }} = :sys.get_state(pid)
    end
  end

  test "unwrap_secrets/3 should load encrypted secrets by decrypting them" do
    {:ok, pid} = Keystore.start_link()

    timestamp = ~U[2021-04-08 06:35:17Z]

    {daily_nonce_seed, transaction_seed, network_pool_seed} =
      load_secrets(~U[2021-04-08 06:35:17Z])

    assert {:authorized,
            %{
              transaction_seed: ^transaction_seed,
              network_pool_seed: ^network_pool_seed,
              daily_nonce_keys: %{^timestamp => {pub, _}}
            }} = :sys.get_state(pid)

    {expected_pub, _} = Crypto.generate_deterministic_keypair(daily_nonce_seed)
    assert pub == expected_pub
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
