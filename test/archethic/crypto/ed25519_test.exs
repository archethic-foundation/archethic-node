defmodule ArchEthic.Crypto.Ed25519Test do
  use ExUnit.Case

  alias ArchEthic.Crypto.Ed25519

  test "generate_keypair/2 should produce a deterministic keypair" do
    assert Ed25519.generate_keypair("myseed") == Ed25519.generate_keypair("myseed")
  end

  test "sign/3 should produce the same signature" do
    {_, pv} = Ed25519.generate_keypair("myseed")
    assert Ed25519.sign(pv, "hello") == Ed25519.sign(pv, "hello")
  end

  test "verify?/4 should return true when the signature is valid" do
    {pub, pv} = Ed25519.generate_keypair("myseed")
    sig = Ed25519.sign(pv, "hello")
    assert Ed25519.verify?(pub, "hello", sig)
  end
end
