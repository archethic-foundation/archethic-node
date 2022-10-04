defmodule Archethic.Crypto.NodeKeystore.Origin.TPMImplTest do
  use ArchethicCase

  alias Archethic.Crypto.NodeKeystore.Origin.TPMImpl

  @tag :infrastructure
  test "origin_public_key/0" do
    {:ok, _} = TPMImpl.start_link()
    assert <<1::8, 2::8, 4::8, _::binary>> = TPMImpl.origin_public_key()
  end

  @tag :infrastructure
  test "sign_with_origin_key/1" do
    {:ok, _} = TPMImpl.start_link()
    <<_::8, _::8, public_key::binary>> = TPMImpl.origin_public_key()
    sig = TPMImpl.sign_with_origin_key("hello")
    assert :crypto.verify(:ecdsa, :sha256, "hello", sig, [public_key, :secp256r1])
  end

  @tag :infrastructure
  test "retrieve_node_seed/0" do
    {:ok, pid} = TPMImpl.start_link()
    seed = TPMImpl.retrieve_node_seed()
    ^seed = TPMImpl.retrieve_node_seed()
    GenServer.stop(pid)
    {:ok, _} = TPMImpl.start_link()
    ^seed = TPMImpl.retrieve_node_seed()
  end
end
