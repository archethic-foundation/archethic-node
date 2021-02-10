defmodule CryptoTest do
  use UnirisCase, async: false
  use ExUnitProperties

  alias Uniris.Crypto
  alias Uniris.Crypto.ID

  doctest Crypto

  property "symmetric aes encryption and decryption" do
    check all(
            aes_key <- StreamData.binary(length: 32),
            data <- StreamData.binary()
          ) do
      cipher = Crypto.aes_encrypt(data, aes_key)
      is_binary(cipher) and data == Crypto.aes_decrypt!(cipher, aes_key)
    end
  end

  property "symmetric EC encryption and decryption" do
    check all(
            seed <- StreamData.binary(length: 32),
            data <- StreamData.binary(min_length: 1)
          ) do
      {pub, pv} = Crypto.generate_deterministic_keypair(seed, :secp256r1)
      cipher = Crypto.ec_encrypt(data, pub)
      is_binary(cipher) and data == Crypto.ec_decrypt!(cipher, pv)
    end
  end

  property "symmetric EC encryption and decryption with Ed25519" do
    check all(
            seed <- StreamData.binary(min_length: 1),
            data <- StreamData.binary(min_length: 1)
          ) do
      {pub, pv} = Crypto.generate_deterministic_keypair(seed, :ed25519)
      cipher = Crypto.ec_encrypt(data, pub)
      is_binary(cipher) and data == Crypto.ec_decrypt!(cipher, pv)
    end
  end

  test "hash_with_storage_nonce/1 should hash a data using the storage nonce" do
    :persistent_term.put(:storage_nonce, "mynonce")
    assert Crypto.hash(["mynonce", "hello"]) == Crypto.hash_with_storage_nonce("hello")
  end

  test "decrypt_and_set_storage_nonce/1 should decrypt storage nonce using node last key and and load storage nonce" do
    storage_nonce = :crypto.strong_rand_bytes(32)

    assert :ok =
             Crypto.decrypt_and_set_storage_nonce(
               Crypto.ec_encrypt(storage_nonce, Crypto.node_public_key())
             )

    assert {:ok, _} = File.read(Application.app_dir(:uniris, "priv/crypto/storage_nonce"))
    File.rm(Application.app_dir(:uniris, "priv/crypto/storage_nonce"))
  end

  test "encrypt_storage_nonce/1 should encrypt storage nonce using a public key" do
    {pub, pv} = Crypto.derive_keypair("seed", 0)
    :persistent_term.put(:storage_nonce, "nonce")

    assert "nonce" ==
             pub
             |> Crypto.encrypt_storage_nonce()
             |> Crypto.ec_decrypt!(pv)
  end
end
