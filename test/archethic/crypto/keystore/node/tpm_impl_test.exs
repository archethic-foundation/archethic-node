defmodule ArchEthic.Crypto.NodeKeystore.TPMImplTest do
  use ArchEthicCase

  alias ArchEthic.Crypto.NodeKeystore.TPMImpl

  @tag :infrastructure
  test "first_public_key/0" do
    {:ok, _} = TPMImpl.start_link()
    assert <<1::8, 1::8, 4::8, _::binary>> = TPMImpl.first_public_key()
  end

  @tag :infrastructure
  test "last_public_key/0" do
    {:ok, _} = TPMImpl.start_link()
    assert <<1::8, 1::8, 4::8, _::binary>> = TPMImpl.last_public_key()
  end

  @tag :infrastructure
  test "previous_public_key/0" do
    {:ok, _} = TPMImpl.start_link()
    assert <<1::8, 1::8, 4::8, _::binary>> = TPMImpl.previous_public_key()
  end

  @tag :infrastructure
  test "next_public_key/0" do
    {:ok, _} = TPMImpl.start_link()
    assert <<1::8, 1::8, 4::8, _::binary>> = TPMImpl.next_public_key()
  end

  @tag :infrastructure
  test "sign_with_first_key/1" do
    {:ok, _} = TPMImpl.start_link()
    <<_::8, _::8, public_key::binary>> = TPMImpl.first_public_key()
    sig = TPMImpl.sign_with_first_key("hello")
    assert :crypto.verify(:ecdsa, :sha256, "hello", sig, [public_key, :secp256r1])
  end

  @tag :infrastructure
  test "sign_with_last_key/1" do
    {:ok, _} = TPMImpl.start_link()
    <<_::8, _::8, public_key::binary>> = TPMImpl.last_public_key()
    sig = TPMImpl.sign_with_last_key("hello")
    assert :crypto.verify(:ecdsa, :sha256, "hello", sig, [public_key, :secp256r1])
  end

  @tag :infrastructure
  test "sign_with_previous_key/1" do
    {:ok, _} = TPMImpl.start_link()
    <<_::8, _::8, public_key::binary>> = TPMImpl.previous_public_key()
    sig = TPMImpl.sign_with_previous_key("hello")
    assert :crypto.verify(:ecdsa, :sha256, "hello", sig, [public_key, :secp256r1])
  end

  @tag :infrastructure
  test "diffie_hellman_with_first_key/1" do
    {:ok, _} = TPMImpl.start_link()
    {eph_public_key, eph_private_key} = :crypto.generate_key(:ecdh, :secp256r1)
    shared_secret = TPMImpl.diffie_hellman_with_first_key(eph_public_key)

    <<_::8, _::8, public_key::binary>> = TPMImpl.first_public_key()

    assert shared_secret ==
             :crypto.compute_key(:ecdh, public_key, eph_private_key, :secp256r1)
  end

  @tag :infrastructure
  test "diffie_hellman_with_last_key/1" do
    {:ok, _} = TPMImpl.start_link()
    {eph_public_key, eph_private_key} = :crypto.generate_key(:ecdh, :secp256r1)
    shared_secret = TPMImpl.diffie_hellman_with_last_key(eph_public_key)

    <<_::8, _::8, public_key::binary>> = TPMImpl.last_public_key()

    assert shared_secret ==
             :crypto.compute_key(:ecdh, public_key, eph_private_key, :secp256r1)
  end
end
