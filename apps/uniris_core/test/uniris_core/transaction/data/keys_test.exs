defmodule UnirisCore.TransactionData.KeysTest do
  use ExUnit.Case

  doctest UnirisCore.TransactionData.Keys

  alias UnirisCore.Crypto
  alias UnirisCore.TransactionData.Keys

  test "new/3 create new transaction data keys and encrypt secret key with authorized public keys" do
    secret_key = :crypto.strong_rand_bytes(32)
    secret = Crypto.aes_encrypt("important message", secret_key)
    {pub, pv} = UnirisCore.Crypto.generate_deterministic_keypair("seed", :secp256r1)

    %Keys{authorized_keys: authorized_keys, secret: secret} =
      UnirisCore.TransactionData.Keys.new([pub], secret_key, secret)

    assert Map.has_key?(authorized_keys, pub)
    encrypted_key = Map.get(authorized_keys, pub)

    secret_key = Crypto.ec_decrypt!(encrypted_key, pv)
    assert "important message" == Crypto.aes_decrypt!(secret, secret_key)
  end
end
