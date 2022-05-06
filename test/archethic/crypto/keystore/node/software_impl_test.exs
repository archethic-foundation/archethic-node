defmodule Archethic.Crypto.NodeKeystore.SoftwareImplTest do
  use ArchethicCase

  alias Archethic.Crypto
  alias Archethic.Crypto.Ed25519
  alias Archethic.Crypto.NodeKeystore.SoftwareImpl, as: Keystore

  import Mox

  setup :set_mox_global

  describe "start_link/1" do
    test "should set the last keypair to the first keypair if no previous transaction found" do
      {:ok, pid} = Keystore.start_link(seed: "fake seed")

      first_keypair = Crypto.derive_keypair("fake seed", 0)
      next_keypair = Crypto.derive_keypair("fake seed", 1)

      assert %{
               first_keypair: ^first_keypair,
               last_keypair: ^first_keypair,
               next_keypair: ^next_keypair
             } = :sys.get_state(pid)
    end

    test "should set the last keypair based on the previous transaction found" do
      MockDB
      |> stub(:get_bootstrap_info, fn "node_keys_index" -> "3" end)

      {:ok, pid} = Keystore.start_link(seed: "fake seed")

      first_keypair = Crypto.derive_keypair("fake seed", 0)
      last_keypair = Crypto.derive_keypair("fake seed", 2)
      previous_keypair = Crypto.derive_keypair("fake seed", 3)
      next_keypair = Crypto.derive_keypair("fake seed", 4)

      assert %{
               first_keypair: ^first_keypair,
               last_keypair: ^last_keypair,
               previous_keypair: ^previous_keypair,
               next_keypair: ^next_keypair
             } = :sys.get_state(pid)
    end
  end

  test "first_public_key/0 should return the first node public key" do
    {pub, _} = Crypto.derive_keypair("fake seed", 0)
    {:ok, _pid} = Keystore.start_link(seed: "fake seed")

    assert pub == Keystore.first_public_key()
  end

  test "last_public_key/0 should return the first node public key" do
    {pub, _} = Crypto.derive_keypair("fake seed", 0)
    {:ok, _pid} = Keystore.start_link(seed: "fake seed")

    assert pub == Keystore.last_public_key()
  end

  test "next_public_key/0 should return the next node public key" do
    {pub, _} = Crypto.derive_keypair("fake seed", 1)
    {:ok, _pid} = Keystore.start_link(seed: "fake seed")

    assert pub == Keystore.next_public_key()
  end

  test "sign_with_first_key/1 should sign the data with the first node private key" do
    {_, pv} = Crypto.derive_keypair("fake seed", 0)
    {:ok, _pid} = Keystore.start_link(seed: "fake seed")

    expected_sign = Crypto.sign("hello", pv)
    assert expected_sign == Keystore.sign_with_first_key("hello")
  end

  test "sign_with_last_key/1 should sign the data with the last node private key" do
    {_, pv} = Crypto.derive_keypair("fake seed", 0)
    {:ok, _pid} = Keystore.start_link(seed: "fake seed")

    expected_sign = Crypto.sign("hello", pv)
    assert expected_sign == Keystore.sign_with_last_key("hello")
  end

  test "diffie_helman_with_last_key/1 should perform a ecdh with the last node private key" do
    {_, <<_::8, _::8, pv::binary>>} = Crypto.derive_keypair("fake seed", 0)
    {:ok, _pid} = Keystore.start_link(seed: "fake seed")

    {<<_::8, _::8, pub::binary>>, _} = Crypto.generate_random_keypair()

    x25519_sk = Ed25519.convert_to_x25519_private_key(pv)
    ecdh = :crypto.compute_key(:ecdh, pub, x25519_sk, :x25519)

    assert Keystore.diffie_hellman_with_last_key(pub) == ecdh
  end
end
