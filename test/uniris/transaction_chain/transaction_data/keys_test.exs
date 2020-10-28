defmodule Uniris.TransactionChain.TransactionData.KeysTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Uniris.Crypto
  alias Uniris.TransactionChain.TransactionData.Keys

  doctest Keys

  test "new/3 create new transaction data keys and encrypt secret key with authorized public keys" do
    secret_key = :crypto.strong_rand_bytes(32)
    secret = Crypto.aes_encrypt("important message", secret_key)
    {pub, pv} = Crypto.generate_deterministic_keypair("seed", :secp256r1)
    {pub2, pv2} = Crypto.generate_deterministic_keypair("other_seed")

    %Keys{authorized_keys: authorized_keys, secret: secret} =
      Keys.new([pub, pub2], secret_key, secret)

    assert Map.has_key?(authorized_keys, pub)
    encrypted_key = Map.get(authorized_keys, pub)

    secret_key = Crypto.ec_decrypt!(encrypted_key, pv)
    assert "important message" == Crypto.aes_decrypt!(secret, secret_key)

    encrypted_key = Map.get(authorized_keys, pub2)

    secret_key = Crypto.ec_decrypt!(encrypted_key, pv2)
    assert "important message" == Crypto.aes_decrypt!(secret, secret_key)
  end

  property "symmetric serialization/deserialization" do
    check all(
            secret <- StreamData.binary(min_length: 1),
            seeds <- StreamData.list_of(StreamData.binary(length: 32)),
            secret_key <- StreamData.binary(length: 32)
          ) do
      public_keys =
        Enum.map(seeds, fn seed ->
          {pub, _} = Crypto.generate_deterministic_keypair(seed, :secp256r1)
          pub
        end)

      {keys, _} =
        public_keys
        |> Keys.new(secret_key, secret)
        |> Keys.serialize()
        |> Keys.deserialize()

      assert keys.secret == secret

      assert Enum.all?(Map.keys(keys.authorized_keys), &(&1 in public_keys))
    end
  end
end
