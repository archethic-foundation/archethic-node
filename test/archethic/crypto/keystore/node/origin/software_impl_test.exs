defmodule Archethic.Crypto.NodeKeystore.Origin.SoftwareImplTest do
  use ArchethicCase

  alias Archethic.Crypto
  alias Archethic.Crypto.NodeKeystore.Origin.SoftwareImpl, as: Keystore

  import Mox

  setup :set_mox_global

  describe "start_link/1" do
    test "should start the process with the origin keypair" do
      {:ok, pid} = Keystore.start_link()
      assert %{origin_keypair: {_pub, _pv}} = :sys.get_state(pid)
    end
  end

  test "origin_public_key/0 should return the origin's public key" do
    {:ok, pid} = Keystore.start_link()
    %{origin_keypair: {pub, _pv}} = :sys.get_state(pid)
    assert pub == Keystore.origin_public_key(pid)
  end

  test "sign_with_origin_key/1 should sign the data with the origin's node private key" do
    {:ok, pid} = Keystore.start_link()
    %{origin_keypair: {pub, _pv}} = :sys.get_state(pid)
    sig = Keystore.sign_with_origin_key(pid, "hello")

    assert Crypto.verify?(sig, "hello", pub)
  end
end
