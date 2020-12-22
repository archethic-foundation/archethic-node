defmodule Uniris.Crypto.SoftwareKeystoreTest do
  use UnirisCase

  alias Uniris.Crypto
  alias Uniris.Crypto.SoftwareKeystore

  import Mox

  setup :set_mox_global

  setup do
    SoftwareKeystore.start_link(seed: "fake seed")
    :ok
  end

  test "node_public_key/0 should return the last node public key" do
    {pub, _} = Crypto.derive_keypair(Application.get_env(:uniris, SoftwareKeystore)[:seed], 0)
    assert pub == SoftwareKeystore.node_public_key()
  end

  test "node_public_key/1 should return the a given node public key" do
    {pub, _} = Crypto.derive_keypair(Application.get_env(:uniris, SoftwareKeystore)[:seed], 2)
    assert pub == SoftwareKeystore.node_public_key(2)
  end

  test "sign_with_node_key/1 should sign the data with the latest node private key" do
    {_, pv} = Crypto.derive_keypair(Application.get_env(:uniris, SoftwareKeystore)[:seed], 0)

    expected_sign = Crypto.sign("hello", pv)
    assert expected_sign == SoftwareKeystore.sign_with_node_key("hello")
  end

  test "sign_with_node_key/2 should sign the data with a given node private key" do
    {_, pv} = Crypto.derive_keypair(Application.get_env(:uniris, SoftwareKeystore)[:seed], 5)

    expected_sign = Crypto.sign("hello", pv)
    assert expected_sign == SoftwareKeystore.sign_with_node_key("hello", 5)
  end

  test "decrypt_with_node_key!/1 should decrypt data with the latest node private key" do
    public_key = SoftwareKeystore.node_public_key()
    cipher = Crypto.ec_encrypt("hello", public_key)

    assert "hello" == SoftwareKeystore.decrypt_with_node_key!(cipher)
  end

  test "decrypt_with_node_key!/2 should decrypt data with a given node private key" do
    public_key = SoftwareKeystore.node_public_key(2)
    cipher = Crypto.ec_encrypt("hello", public_key)

    assert "hello" == SoftwareKeystore.decrypt_with_node_key!(cipher, 2)
  end

  test "number_of_node_keys/0 should return the last index of generated node keys" do
    assert 0 == SoftwareKeystore.number_of_node_keys()
  end

  test "increment_number_of_generate_node_keys/0 should increment the number of generated node keys" do
    assert :ok = SoftwareKeystore.increment_number_of_generate_node_keys()
    assert 1 == SoftwareKeystore.number_of_node_keys()
  end

  test "number_of_node_shared_secrets_keys/0 should return the last index of generated node shared keys" do
    SoftwareKeystore.start_link(seed: "seed")
    assert 0 == SoftwareKeystore.number_of_node_shared_secrets_keys()
  end

  test "increment_number_of_generate_node_shared_keys/0 should increment the number of generated node shared keys" do
    assert :ok = SoftwareKeystore.increment_number_of_generate_node_shared_secrets_keys()
    assert 1 == SoftwareKeystore.number_of_node_shared_secrets_keys()
  end

  test "decrypt_and_set_daily_nonce_seed/2 should load daily nonce keys by decrypting the seed" do
    public_key = SoftwareKeystore.node_public_key()
    aes_key = :crypto.strong_rand_bytes(32)
    daily_nonce_seed = :crypto.strong_rand_bytes(32)

    encrypted_nonce = Crypto.aes_encrypt(daily_nonce_seed, aes_key)
    encrypted_key = Crypto.ec_encrypt(aes_key, public_key)

    assert :ok = SoftwareKeystore.decrypt_and_set_daily_nonce_seed(encrypted_nonce, encrypted_key)
    %{daily_nonce_keys: {pub, _}} = :sys.get_state(SoftwareKeystore)
    {expected_pub, _} = Crypto.generate_deterministic_keypair(daily_nonce_seed)
    assert pub == expected_pub
  end

  test "hash_with_daily_nonce/1 should hash with daily nonce private key" do
    public_key = SoftwareKeystore.node_public_key()
    aes_key = :crypto.strong_rand_bytes(32)
    daily_nonce_seed = :crypto.strong_rand_bytes(32)

    encrypted_nonce = Crypto.aes_encrypt(daily_nonce_seed, aes_key)
    encrypted_key = Crypto.ec_encrypt(aes_key, public_key)

    assert :ok = SoftwareKeystore.decrypt_and_set_daily_nonce_seed(encrypted_nonce, encrypted_key)
    {_, pv} = Crypto.generate_deterministic_keypair(daily_nonce_seed)

    assert Crypto.hash([pv, "hello"]) == SoftwareKeystore.hash_with_daily_nonce("hello")
  end

  test "decrypt_and_set_node_shared_secrets_transaction_seed/2 should load node shared secrets seed by decrypting it" do
    public_key = SoftwareKeystore.node_public_key()
    aes_key = :crypto.strong_rand_bytes(32)
    transaction_seed = :crypto.strong_rand_bytes(32)

    encrypted_nonce = Crypto.aes_encrypt(transaction_seed, aes_key)
    encrypted_key = Crypto.ec_encrypt(aes_key, public_key)

    assert :ok =
             SoftwareKeystore.decrypt_and_set_node_shared_secrets_transaction_seed(
               encrypted_nonce,
               encrypted_key
             )

    assert %{node_secrets_transaction_seed: ^transaction_seed} = :sys.get_state(SoftwareKeystore)
  end

  test "sign_with_node_shared_secrets_key/1 should sign the data with the latest node shared secrets private key" do
    public_key = SoftwareKeystore.node_public_key()
    aes_key = :crypto.strong_rand_bytes(32)
    transaction_seed = :crypto.strong_rand_bytes(32)

    encrypted_nonce = Crypto.aes_encrypt(transaction_seed, aes_key)
    encrypted_key = Crypto.ec_encrypt(aes_key, public_key)

    :ok =
      SoftwareKeystore.decrypt_and_set_node_shared_secrets_transaction_seed(
        encrypted_nonce,
        encrypted_key
      )

    {_, pv} = Crypto.derive_keypair(transaction_seed, 0)

    assert Crypto.sign("hello", pv) == SoftwareKeystore.sign_with_node_shared_secrets_key("hello")
  end

  test "sign_with_node_shared_secrets_key/2 should sign the data with a given node shared secrets private key" do
    public_key = SoftwareKeystore.node_public_key()
    aes_key = :crypto.strong_rand_bytes(32)
    transaction_seed = :crypto.strong_rand_bytes(32)

    encrypted_nonce = Crypto.aes_encrypt(transaction_seed, aes_key)
    encrypted_key = Crypto.ec_encrypt(aes_key, public_key)

    :ok =
      SoftwareKeystore.decrypt_and_set_node_shared_secrets_transaction_seed(
        encrypted_nonce,
        encrypted_key
      )

    {_, pv} = Crypto.derive_keypair(transaction_seed, 2)

    assert Crypto.sign("hello", pv) ==
             SoftwareKeystore.sign_with_node_shared_secrets_key("hello", 2)
  end

  test "node_shared_secrets_public_key/1 should return a given node shared secrets public key" do
    public_key = SoftwareKeystore.node_public_key()
    aes_key = :crypto.strong_rand_bytes(32)
    transaction_seed = :crypto.strong_rand_bytes(32)

    encrypted_nonce = Crypto.aes_encrypt(transaction_seed, aes_key)
    encrypted_key = Crypto.ec_encrypt(aes_key, public_key)

    :ok =
      SoftwareKeystore.decrypt_and_set_node_shared_secrets_transaction_seed(
        encrypted_nonce,
        encrypted_key
      )

    {pub, _} = Crypto.derive_keypair(transaction_seed, 2)
    assert pub == SoftwareKeystore.node_shared_secrets_public_key(2)
  end

  test "load update of node derived keys" do
    Enum.each(0..100, fn i ->
      :ok = SoftwareKeystore.increment_number_of_generate_node_keys()
      assert SoftwareKeystore.node_public_key(i - 1) != SoftwareKeystore.node_public_key()
    end)
  end

  test "load update of node shared secrets derived keys" do
    public_key = SoftwareKeystore.node_public_key()
    aes_key = :crypto.strong_rand_bytes(32)
    transaction_seed = :crypto.strong_rand_bytes(32)

    encrypted_nonce = Crypto.aes_encrypt(transaction_seed, aes_key)
    encrypted_key = Crypto.ec_encrypt(aes_key, public_key)

    :ok =
      SoftwareKeystore.decrypt_and_set_node_shared_secrets_transaction_seed(
        encrypted_nonce,
        encrypted_key
      )

    Enum.each(0..100, fn i ->
      SoftwareKeystore.increment_number_of_generate_node_shared_secrets_keys()

      assert SoftwareKeystore.node_shared_secrets_public_key(i - 1) !=
               SoftwareKeystore.node_shared_secrets_public_key(i)
    end)
  end
end
