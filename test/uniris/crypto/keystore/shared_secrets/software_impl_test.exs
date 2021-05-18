defmodule Uniris.Crypto.SharedSecrets.SoftwareImplTest do
  use UnirisCase
  use ExUnitProperties

  alias Uniris.Crypto
  alias Uniris.Crypto.KeystoreCounter
  alias Uniris.Crypto.SharedSecretsKeystore.SoftwareImpl, as: Keystore

  import Mox

  setup :set_mox_global

  setup do
    Keystore.start_link()
    :ok
  end

  test "unwrap_secrets/3 should load encrypted secrets by decrypting them" do
    timestamp = ~U[2021-04-08 06:35:17Z]

    {daily_nonce_seed, transaction_seed, network_pool_seed} =
      load_secrets(~U[2021-04-08 06:35:17Z])

    assert {:authorized,
            %{
              transaction_seed: ^transaction_seed,
              network_pool_seed: ^network_pool_seed,
              daily_nonce_keys: %{^timestamp => {pub, _}}
            }} = :sys.get_state(Keystore)

    {expected_pub, _} = Crypto.generate_deterministic_keypair(daily_nonce_seed)
    assert pub == expected_pub
  end

  test "sign_with_node_shared_secrets_key/1 should sign the data with the latest node shared secrets private key" do
    {_, transaction_seed, _} = load_secrets(~U[2021-04-08 06:35:17Z])
    {_, pv} = Crypto.derive_keypair(transaction_seed, 0)

    assert Crypto.sign("hello", pv) == Keystore.sign_with_node_shared_secrets_key("hello")
  end

  test "sign_with_node_shared_secrets_key/2 should sign the data with a given node shared secrets private key" do
    {_, transaction_seed, _} = load_secrets(~U[2021-04-08 06:35:17Z])
    {_, pv} = Crypto.derive_keypair(transaction_seed, 2)

    assert Crypto.sign("hello", pv) ==
             Keystore.sign_with_node_shared_secrets_key("hello", 2)
  end

  test "node_shared_secrets_public_key/1 should return a given node shared secrets public key" do
    {_, transaction_seed, _} = load_secrets(~U[2021-04-08 06:35:17Z])
    {pub, _} = Crypto.derive_keypair(transaction_seed, 2)

    assert pub == Keystore.node_shared_secrets_public_key(2)
  end

  test "sign_with_network_pool_key/1 should sign the data with the latest network pool private key" do
    {_, _, network_pool_seed} = load_secrets(~U[2021-04-08 06:35:17Z])
    {_, pv} = Crypto.derive_keypair(network_pool_seed, 0)

    assert Crypto.sign("hello", pv) == Keystore.sign_with_network_pool_key("hello")
  end

  test "sign_with_network_pool_key/2 should sign the data with a given network pool private key" do
    {_, _, network_pool_seed} = load_secrets(~U[2021-04-08 06:35:17Z])
    {_, pv} = Crypto.derive_keypair(network_pool_seed, 2)

    assert Crypto.sign("hello", pv) == Keystore.sign_with_network_pool_key("hello", 2)
  end

  test "network_pool_public_key/1 should return a given network pool public key" do
    {_, _, network_pool_seed} = load_secrets(~U[2021-04-08 06:35:17Z])
    {pub, _} = Crypto.derive_keypair(network_pool_seed, 2)

    assert pub == Keystore.network_pool_public_key(2)
  end

  property "node_shared_secrets_public_key/1 should not be equal to the previous one" do
    check all(nb_keys <- StreamData.positive_integer()) do
      load_secrets(~U[2021-04-08 06:35:17Z])

      KeystoreCounter.set_node_shared_secrets_key_counter(nb_keys)

      assert Keystore.node_shared_secrets_public_key(nb_keys - 1) !=
               Keystore.node_shared_secrets_public_key(nb_keys)
    end
  end

  property "network_pool_public_key/1 should not be equal to the previous one" do
    check all(nb_keys <- StreamData.positive_integer()) do
      load_secrets(~U[2021-04-08 06:35:17Z])

      KeystoreCounter.set_node_shared_secrets_key_counter(nb_keys)

      assert Keystore.network_pool_public_key(nb_keys - 1) !=
               Keystore.network_pool_public_key(nb_keys)
    end
  end

  defp load_secrets(timestamp = %DateTime{}) do
    public_key = Crypto.node_public_key()
    aes_key = :crypto.strong_rand_bytes(32)

    daily_nonce_seed = :crypto.strong_rand_bytes(32)
    transaction_seed = :crypto.strong_rand_bytes(32)
    network_pool_seed = :crypto.strong_rand_bytes(32)

    encrypted_daily_nonce_seed = Crypto.aes_encrypt(daily_nonce_seed, aes_key)
    encrypted_transaction_seed = Crypto.aes_encrypt(transaction_seed, aes_key)
    encrypted_network_pool_seed = Crypto.aes_encrypt(network_pool_seed, aes_key)

    encrypted_key = Crypto.ec_encrypt(aes_key, public_key)

    secrets =
      <<encrypted_daily_nonce_seed::binary, encrypted_transaction_seed::binary,
        encrypted_network_pool_seed::binary>>

    assert :ok = Keystore.unwrap_secrets(secrets, encrypted_key, timestamp)

    {daily_nonce_seed, transaction_seed, network_pool_seed}
  end
end
