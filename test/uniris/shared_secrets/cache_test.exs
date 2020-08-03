defmodule Uniris.SharedSecrets.CacheTest do
  use ExUnit.Case, async: false

  alias Uniris.Crypto
  alias Uniris.SharedSecrets.Cache

  test "add_origin_public_key/1 should update the list of origin public keys" do
    {pub, _} = Crypto.generate_deterministic_keypair("hello")
    Cache.add_origin_public_key(:software, pub)
    assert pub in Cache.origin_public_keys()
  end

  test "origin_public_keys/1 should only get the origin public key for a given family" do
    {pub, _} = Crypto.generate_deterministic_keypair("hello")
    Cache.add_origin_public_key(:usb, pub)
    assert pub in Cache.origin_public_keys(:usb)
  end

  test "origin_public_keys/0 should get all the origin public keys" do
    {pub, _} = Crypto.generate_deterministic_keypair("seed1")
    Cache.add_origin_public_key(:usb, pub)
    {pub2, _} = Crypto.generate_deterministic_keypair("seed2")
    Cache.add_origin_public_key(:software, pub2)
    assert Enum.all?([pub, pub2], &(&1 in Cache.origin_public_keys()))
  end
end
