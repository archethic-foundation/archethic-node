defmodule Archethic.Crypto.NodeKeystore.SoftwareImplTest do
  use ArchethicCase

  alias Archethic.Crypto
  alias Archethic.Crypto.Ed25519
  alias Archethic.Crypto.NodeKeystore.SoftwareImpl, as: Keystore

  import Mox

  setup :set_mox_global

  setup do
    on_exit(fn ->
      File.rm_rf!(Archethic.Utils.mut_dir())
    end)

    impl = Application.get_env(:archethic, Archethic.Crypto.NodeKeystore.Origin)
    seed = impl.retrieve_node_seed()

    {:ok, %{seed: seed}}
  end

  describe "start_link/1" do
    test "should set the last keypair to the first keypair if no previous transaction found", %{
      seed: seed
    } do
      {:ok, _} = Keystore.start_link()
      first_keypair = Crypto.derive_keypair(seed, 0)
      next_keypair = Crypto.derive_keypair(seed, 1)

      assert elem(first_keypair, 0) == Keystore.first_public_key()
      assert elem(next_keypair, 0) == Keystore.next_public_key()

      assert "0" == File.read!(Archethic.Utils.mut_dir("crypto/index"))
    end

    test "should set the last keypair based on the previous transaction found", %{seed: seed} do
      File.mkdir_p!(Archethic.Utils.mut_dir("crypto"))
      File.write!(Archethic.Utils.mut_dir("crypto/index"), "3")

      {:ok, _} = Keystore.start_link()

      first_keypair = Crypto.derive_keypair(seed, 0)
      last_keypair = Crypto.derive_keypair(seed, 2)
      previous_keypair = Crypto.derive_keypair(seed, 3)
      next_keypair = Crypto.derive_keypair(seed, 4)

      assert elem(first_keypair, 0) == Keystore.first_public_key()
      assert elem(next_keypair, 0) == Keystore.next_public_key()
      assert elem(previous_keypair, 0) == Keystore.previous_public_key()
      assert elem(last_keypair, 0) == Keystore.last_public_key()
    end
  end

  test "first_public_key/0 should return the first node public key", %{seed: seed} do
    {:ok, _} = Keystore.start_link()
    {pub, _} = Crypto.derive_keypair(seed, 0)
    assert pub == Keystore.first_public_key()
  end

  test "last_public_key/0 should return the first node public key", %{seed: seed} do
    {:ok, _} = Keystore.start_link()
    {pub, _} = Crypto.derive_keypair(seed, 0)
    assert pub == Keystore.last_public_key()
  end

  test "next_public_key/0 should return the next node public key", %{seed: seed} do
    {:ok, _} = Keystore.start_link()
    {pub, _} = Crypto.derive_keypair(seed, 1)
    assert pub == Keystore.next_public_key()
  end

  test "sign_with_first_key/1 should sign the data with the first node private key", %{seed: seed} do
    {:ok, _} = Keystore.start_link()
    {_, pv} = Crypto.derive_keypair(seed, 0)
    expected_sign = Crypto.sign("hello", pv)
    assert expected_sign == Keystore.sign_with_first_key("hello")
  end

  test "sign_with_last_key/1 should sign the data with the last node private key", %{seed: seed} do
    {:ok, _} = Keystore.start_link()
    {_, pv} = Crypto.derive_keypair(seed, 0)
    expected_sign = Crypto.sign("hello", pv)
    assert expected_sign == Keystore.sign_with_last_key("hello")
  end

  test "diffie_helman_with_last_key/1 should perform a ecdh with the last node private key", %{
    seed: seed
  } do
    {:ok, _} = Keystore.start_link()
    {_, <<_::8, _::8, pv::binary>>} = Crypto.derive_keypair(seed, 0)
    {<<_::8, _::8, pub::binary>>, _} = Crypto.generate_random_keypair()

    x25519_sk = Ed25519.convert_to_x25519_private_key(pv)
    ecdh = :crypto.compute_key(:ecdh, pub, x25519_sk, :x25519)

    assert Keystore.diffie_hellman_with_last_key(pub) == ecdh
  end
end
