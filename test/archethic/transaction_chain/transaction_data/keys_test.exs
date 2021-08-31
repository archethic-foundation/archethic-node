defmodule ArchEthic.TransactionChain.TransactionData.KeysTest do
  use ExUnit.Case
  use ExUnitProperties

  alias ArchEthic.Crypto
  alias ArchEthic.TransactionChain.TransactionData.Keys

  doctest Keys

  test "new/3 create new transaction data keys and encrypt secret key with authorized public keys" do
    secret_key = :crypto.strong_rand_bytes(32)
    secret = Crypto.aes_encrypt("important message", secret_key)
    {pub, pv} = Crypto.generate_deterministic_keypair("seed", :secp256r1)
    {pub2, pv2} = Crypto.generate_deterministic_keypair("other_seed")

    %Keys{secrets: [secret]} = keys = Keys.add_secret(%Keys{}, secret, secret_key, [pub, pub2])

    assert Keys.authorized_key?(keys, pub)
    encrypted_key = Keys.get_encrypted_key_at(keys, 0, pub)
    secret_key = Crypto.ec_decrypt!(encrypted_key, pv)
    assert "important message" == Crypto.aes_decrypt!(secret, secret_key)

    encrypted_key = Keys.get_encrypted_key_at(keys, 0, pub2)

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

      {keys, _} =
        %Keys{}
        |> Keys.add_secret(secret, secret_key, public_keys)
        |> Keys.serialize()
        |> Keys.deserialize()

      assert keys.secrets == [secret]

      assert Enum.all?(Keys.list_authorized_public_keys(keys), &(&1 in public_keys))
    end
  end
end
