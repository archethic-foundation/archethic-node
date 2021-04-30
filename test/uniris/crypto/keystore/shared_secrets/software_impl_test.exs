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

  test "decrypt_and_set_daily_nonce_seed/3 should load daily nonce keys by decrypting the seed" do
    public_key = Crypto.node_public_key()
    aes_key = :crypto.strong_rand_bytes(32)
    daily_nonce_seed = :crypto.strong_rand_bytes(32)

    encrypted_nonce = Crypto.aes_encrypt(daily_nonce_seed, aes_key)
    encrypted_key = Crypto.ec_encrypt(aes_key, public_key)

    timestamp = ~U[2021-04-08 06:35:17Z]

    assert :ok =
             Keystore.decrypt_and_set_daily_nonce_seed(
               encrypted_nonce,
               encrypted_key,
               timestamp
             )

    %{daily_nonce_keys: %{^timestamp => {pub, _}}} = :sys.get_state(Keystore)
    {expected_pub, _} = Crypto.generate_deterministic_keypair(daily_nonce_seed)
    assert pub == expected_pub
  end

  test "sign_with_daily_nonce_key/2 should sign the data with the closest daily nonce private key at the given timestamp" do
    public_key = Crypto.node_public_key()
    aes_key = :crypto.strong_rand_bytes(32)
    daily_nonce_seed = :crypto.strong_rand_bytes(32)

    encrypted_nonce = Crypto.aes_encrypt(daily_nonce_seed, aes_key)
    encrypted_key = Crypto.ec_encrypt(aes_key, public_key)

    assert :ok =
             Keystore.decrypt_and_set_daily_nonce_seed(
               encrypted_nonce,
               encrypted_key,
               ~U[2021-04-08 06:29:28Z]
             )

    {_, pv} = Crypto.generate_deterministic_keypair(daily_nonce_seed)

    assert Crypto.sign("hello", pv) ==
             Keystore.sign_with_daily_nonce_key(
               "hello",
               ~U[2021-04-08 06:29:30Z]
             )

    daily_nonce_seed2 = :crypto.strong_rand_bytes(32)
    encrypted_nonce2 = Crypto.aes_encrypt(daily_nonce_seed2, aes_key)

    assert :ok =
             Keystore.decrypt_and_set_daily_nonce_seed(
               encrypted_nonce2,
               encrypted_key,
               ~U[2021-04-08 06:29:40Z]
             )

    {_, pv2} = Crypto.generate_deterministic_keypair(daily_nonce_seed2)

    assert Crypto.sign("hello", pv) ==
             Keystore.sign_with_daily_nonce_key(
               "hello",
               ~U[2021-04-08 06:29:30Z]
             )

    assert Crypto.sign("hello", pv) ==
             Keystore.sign_with_daily_nonce_key(
               "hello",
               ~U[2021-04-08 06:29:39Z]
             )

    assert Crypto.sign("hello", pv2) ==
             Keystore.sign_with_daily_nonce_key(
               "hello",
               ~U[2021-04-08 06:29:40Z]
             )

    assert Crypto.sign("hello", pv2) ==
             Keystore.sign_with_daily_nonce_key(
               "hello",
               ~U[2021-04-08 06:29:41Z]
             )
  end

  test "decrypt_and_set_node_shared_secrets_transaction_seed/2 should load node shared secrets seed by decrypting it" do
    public_key = Crypto.node_public_key()
    aes_key = :crypto.strong_rand_bytes(32)
    transaction_seed = :crypto.strong_rand_bytes(32)

    encrypted_nonce = Crypto.aes_encrypt(transaction_seed, aes_key)
    encrypted_key = Crypto.ec_encrypt(aes_key, public_key)

    assert :ok =
             Keystore.decrypt_and_set_node_shared_secrets_transaction_seed(
               encrypted_nonce,
               encrypted_key
             )

    assert %{node_secrets_transaction_seed: ^transaction_seed} = :sys.get_state(Keystore)
  end

  test "decrypt_and_set_node_shared_secrets_network_pool_seed/2 should load network pool seed by decrypting it" do
    public_key = Crypto.node_public_key()
    aes_key = :crypto.strong_rand_bytes(32)
    network_pool_seed = :crypto.strong_rand_bytes(32)

    encrypted_nonce = Crypto.aes_encrypt(network_pool_seed, aes_key)
    encrypted_key = Crypto.ec_encrypt(aes_key, public_key)

    assert :ok =
             Keystore.decrypt_and_set_node_shared_secrets_network_pool_seed(
               encrypted_nonce,
               encrypted_key
             )

    assert %{network_pool_seed: ^network_pool_seed} = :sys.get_state(Keystore)
  end

  test "sign_with_node_shared_secrets_key/1 should sign the data with the latest node shared secrets private key" do
    public_key = Crypto.node_public_key()
    aes_key = :crypto.strong_rand_bytes(32)
    transaction_seed = :crypto.strong_rand_bytes(32)

    encrypted_nonce = Crypto.aes_encrypt(transaction_seed, aes_key)
    encrypted_key = Crypto.ec_encrypt(aes_key, public_key)

    :ok =
      Keystore.decrypt_and_set_node_shared_secrets_transaction_seed(
        encrypted_nonce,
        encrypted_key
      )

    {_, pv} = Crypto.derive_keypair(transaction_seed, 0)

    assert Crypto.sign("hello", pv) == Keystore.sign_with_node_shared_secrets_key("hello")
  end

  test "sign_with_node_shared_secrets_key/2 should sign the data with a given node shared secrets private key" do
    public_key = Crypto.node_public_key()
    aes_key = :crypto.strong_rand_bytes(32)
    transaction_seed = :crypto.strong_rand_bytes(32)

    encrypted_nonce = Crypto.aes_encrypt(transaction_seed, aes_key)
    encrypted_key = Crypto.ec_encrypt(aes_key, public_key)

    :ok =
      Keystore.decrypt_and_set_node_shared_secrets_transaction_seed(
        encrypted_nonce,
        encrypted_key
      )

    {_, pv} = Crypto.derive_keypair(transaction_seed, 2)

    assert Crypto.sign("hello", pv) ==
             Keystore.sign_with_node_shared_secrets_key("hello", 2)
  end

  test "node_shared_secrets_public_key/1 should return a given node shared secrets public key" do
    public_key = Crypto.node_public_key()
    aes_key = :crypto.strong_rand_bytes(32)
    transaction_seed = :crypto.strong_rand_bytes(32)

    encrypted_nonce = Crypto.aes_encrypt(transaction_seed, aes_key)
    encrypted_key = Crypto.ec_encrypt(aes_key, public_key)

    :ok =
      Keystore.decrypt_and_set_node_shared_secrets_transaction_seed(
        encrypted_nonce,
        encrypted_key
      )

    {pub, _} = Crypto.derive_keypair(transaction_seed, 2)
    assert pub == Keystore.node_shared_secrets_public_key(2)
  end

  test "sign_with_network_pool_key/1 should sign the data with the latest network pool private key" do
    public_key = Crypto.node_public_key()
    aes_key = :crypto.strong_rand_bytes(32)
    network_pool_seed = :crypto.strong_rand_bytes(32)

    encrypted_nonce = Crypto.aes_encrypt(network_pool_seed, aes_key)
    encrypted_key = Crypto.ec_encrypt(aes_key, public_key)

    :ok =
      Keystore.decrypt_and_set_node_shared_secrets_network_pool_seed(
        encrypted_nonce,
        encrypted_key
      )

    {_, pv} = Crypto.derive_keypair(network_pool_seed, 0)

    assert Crypto.sign("hello", pv) == Keystore.sign_with_network_pool_key("hello")
  end

  test "sign_with_network_pool_key/2 should sign the data with a given network pool private key" do
    public_key = Crypto.node_public_key()
    aes_key = :crypto.strong_rand_bytes(32)
    network_pool_seed = :crypto.strong_rand_bytes(32)

    encrypted_nonce = Crypto.aes_encrypt(network_pool_seed, aes_key)
    encrypted_key = Crypto.ec_encrypt(aes_key, public_key)

    :ok =
      Keystore.decrypt_and_set_node_shared_secrets_network_pool_seed(
        encrypted_nonce,
        encrypted_key
      )

    {_, pv} = Crypto.derive_keypair(network_pool_seed, 2)
    assert Crypto.sign("hello", pv) == Keystore.sign_with_network_pool_key("hello", 2)
  end

  test "network_pool_public_key/1 should return a given network pool public key" do
    public_key = Crypto.node_public_key()
    aes_key = :crypto.strong_rand_bytes(32)
    network_pool_seed = :crypto.strong_rand_bytes(32)

    encrypted_nonce = Crypto.aes_encrypt(network_pool_seed, aes_key)
    encrypted_key = Crypto.ec_encrypt(aes_key, public_key)

    :ok =
      Keystore.decrypt_and_set_node_shared_secrets_network_pool_seed(
        encrypted_nonce,
        encrypted_key
      )

    {pub, _} = Crypto.derive_keypair(network_pool_seed, 2)
    assert pub == Keystore.network_pool_public_key(2)
  end

  property "node_shared_secrets_public_key/1 should not be equal to the previous one" do
    check all(nb_keys <- StreamData.positive_integer()) do
      public_key = Crypto.node_public_key()
      aes_key = :crypto.strong_rand_bytes(32)
      transaction_seed = :crypto.strong_rand_bytes(32)

      encrypted_nonce = Crypto.aes_encrypt(transaction_seed, aes_key)
      encrypted_key = Crypto.ec_encrypt(aes_key, public_key)

      :ok =
        Keystore.decrypt_and_set_node_shared_secrets_transaction_seed(
          encrypted_nonce,
          encrypted_key
        )

      KeystoreCounter.set_node_shared_secrets_key_counter(nb_keys)

      assert Keystore.node_shared_secrets_public_key(nb_keys - 1) !=
               Keystore.node_shared_secrets_public_key(nb_keys)
    end
  end

  property "network_pool_public_key/1 should hould not be equal to the previous one" do
    check all(nb_keys <- StreamData.positive_integer()) do
      public_key = Crypto.node_public_key()
      aes_key = :crypto.strong_rand_bytes(32)
      network_pool_seed = :crypto.strong_rand_bytes(32)

      encrypted_nonce = Crypto.aes_encrypt(network_pool_seed, aes_key)
      encrypted_key = Crypto.ec_encrypt(aes_key, public_key)

      :ok =
        Keystore.decrypt_and_set_node_shared_secrets_network_pool_seed(
          encrypted_nonce,
          encrypted_key
        )

      KeystoreCounter.set_node_shared_secrets_key_counter(nb_keys)

      assert Keystore.network_pool_public_key(nb_keys - 1) !=
               Keystore.network_pool_public_key(nb_keys)
    end
  end
end
