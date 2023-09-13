defmodule Archethic.TransactionChain.TransactionData.OwnershipTest do
  use ArchethicCase
  import ArchethicCase

  use ExUnitProperties

  alias Archethic.Crypto
  alias Archethic.TransactionChain.TransactionData.Ownership

  doctest Ownership

  test "new/3 create new transaction data ownership and encrypt secret key with authorized public keys" do
    secret_key = :crypto.strong_rand_bytes(32)
    secret = Crypto.aes_encrypt("important message", secret_key)
    {pub, pv} = Crypto.generate_deterministic_keypair("seed", :secp256r1)
    {pub2, pv2} = Crypto.generate_deterministic_keypair("other_seed")

    %Ownership{secret: secret} = key = Ownership.new(secret, secret_key, [pub, pub2])

    assert Ownership.authorized_public_key?(key, pub)
    encrypted_key = Ownership.get_encrypted_key(key, pub)
    secret_key = Crypto.ec_decrypt!(encrypted_key, pv)
    assert "important message" == Crypto.aes_decrypt!(secret, secret_key)

    encrypted_key = Ownership.get_encrypted_key(key, pub2)

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
        Ownership.new(secret, secret_key, public_keys)
        |> Ownership.serialize(current_transaction_version())
        |> Ownership.deserialize(current_transaction_version())

      assert key.secret == secret

      assert Enum.all?(Ownership.list_authorized_public_keys(key), &(&1 in public_keys))
    end
  end
end
