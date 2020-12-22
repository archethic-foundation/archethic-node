defmodule Uniris.Crypto.ECDSATest do
  use ExUnit.Case

  alias Uniris.Crypto.ECDSA

  test "generate_keypair/2 should produce a deterministic keypair" do
    assert ECDSA.generate_keypair(:secp256r1, "myseed") ==
             ECDSA.generate_keypair(:secp256r1, "myseed")
  end

  test "sign/3 should produce a different signature" do
    {_, pv} = ECDSA.generate_keypair(:secp256r1, "myseed")
    assert ECDSA.sign(:secp256r1, pv, "hello") != ECDSA.sign(:secp256r1, pv, "hello")
  end

  test "verify/4 should return true when the signature is valid" do
    {pub, pv} = :crypto.generate_key(:ecdh, :secp256r1)
    sig = ECDSA.sign(:secp256r1, pv, "hello")
    assert ECDSA.verify(:secp256r1, pub, "hello", sig)
  end

  test "encrypt/3 should return an cipher with ephemeral key exchange" do
    {pub, _} = :crypto.generate_key(:ecdh, :secp256r1)

    assert <<_key::binary-65, _tag::binary-16, _cipher::binary>> =
             ECDSA.encrypt(:secp256r1, pub, "hello")
  end

  test "decrypt/3 should return an clear text from a cipher" do
    {pub, pv} = :crypto.generate_key(:ecdh, :secp256r1)
    cipher = ECDSA.encrypt(:secp256r1, pub, "hello")
    assert "hello" = ECDSA.decrypt(:secp256r1, pv, cipher)
  end
end
