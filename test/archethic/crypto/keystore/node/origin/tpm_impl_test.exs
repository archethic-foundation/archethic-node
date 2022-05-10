defmodule Archethic.Crypto.NodeKeystore.Origin.TPMImplTest do
  use ArchethicCase

  alias Archethic.Crypto.NodeKeystore.Origin.TPMImpl

  @tag :infrastructure
  test "origin_public_key/0" do
    {:ok, _} = TPMImpl.start_link()
    assert <<1::8, 1::8, 4::8, _::binary>> = TPMImpl.origin_public_key()
  end

  @tag :infrastructure
  test "sign_with_origin_key/1" do
    {:ok, _} = TPMImpl.start_link()
    <<_::8, _::8, public_key::binary>> = TPMImpl.origin_public_key()
    sig = TPMImpl.sign_with_origin_key("hello")
    assert :crypto.verify(:ecdsa, :sha256, "hello", sig, [public_key, :secp256r1])
  end
end
