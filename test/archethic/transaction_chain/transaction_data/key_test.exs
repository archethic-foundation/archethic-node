defmodule ArchEthic.TransactionChain.TransactionData.KeyTest do
  use ExUnit.Case
  use ExUnitProperties

  alias ArchEthic.Crypto
  alias ArchEthic.TransactionChain.TransactionData.Key

  doctest Key

  test "new/3 create new transaction data keys and encrypt secret key with authorized public keys" do
    secret_key = :crypto.strong_rand_bytes(32)
    secret = Crypto.aes_encrypt("important message", secret_key)
    {pub, pv} = Crypto.generate_deterministic_keypair("seed", :secp256r1)
    {pub2, pv2} = Crypto.generate_deterministic_keypair("other_seed")

    %Key{secret: secret} = key = Key.new(secret, secret_key, [pub, pub2])

    assert Key.authorized_public_key?(key, pub)
    encrypted_key = Key.get_encrypted_key(key, pub)
    secret_key = Crypto.ec_decrypt!(encrypted_key, pv)
    assert "important message" == Crypto.aes_decrypt!(secret, secret_key)

    encrypted_key = Key.get_encrypted_key(key, pub2)

    secret_key = Crypto.ec_decrypt!(encrypted_key, pv2)
    assert "important message" == Crypto.aes_decrypt!(secret, secret_key)
  end

  property "symmetric serialization/deserialization" do
    check all(
            secret <- StreamData.binary(min_length: 1),
            seeds <- StreamData.list_of(StreamData.binary(length: 32), min_length: 1),
            secret_key <- StreamData.binary(length: 32)
          ) do
      public_keys =
        Enum.map(seeds, fn seed ->
          {pub, _} = Crypto.generate_deterministic_keypair(seed, :secp256r1)
          pub
        end)

      {key, _} =
        Key.new(secret, secret_key, public_keys)
        |> Key.serialize()
        |> Key.deserialize()

      assert key.secret == secret

      assert Enum.all?(Key.list_authorized_public_keys(key), &(&1 in public_keys))
    end
  end
end
