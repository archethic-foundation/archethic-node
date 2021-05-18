defmodule Uniris.Crypto.NodeKeystore.SoftwareImplTest do
  use UnirisCase
  use ExUnitProperties

  alias Uniris.Crypto
  alias Uniris.Crypto.KeystoreCounter
  alias Uniris.Crypto.NodeKeystore.SoftwareImpl, as: Keystore

  import Mox

  setup :set_mox_global

  setup do
    Keystore.start_link(seed: "fake seed")
    :ok
  end

  test "node_public_key/0 should return the last node public key" do
    {pub, _} = Crypto.derive_keypair("fake seed", 0)
    assert pub == Keystore.node_public_key()
  end

  test "node_public_key/1 should return the a given node public key" do
    {pub, _} = Crypto.derive_keypair("fake seed", 2)
    assert pub == Keystore.node_public_key(2)
  end

  test "sign_with_node_key/1 should sign the data with the latest node private key" do
    {_, pv} = Crypto.derive_keypair("fake seed", 0)

    expected_sign = Crypto.sign("hello", pv)
    assert expected_sign == Keystore.sign_with_node_key("hello")
  end

  test "sign_with_node_key/2 should sign the data with a given node private key" do
    {_, pv} = Crypto.derive_keypair("fake seed", 5)

    expected_sign = Crypto.sign("hello", pv)
    assert expected_sign == Keystore.sign_with_node_key("hello", 5)
  end

  test "diffie_hellman/1 should produce a shared secret with the latest node private key" do
    {<<_::8, pub::binary>>, _} = Crypto.generate_deterministic_keypair("otherseed")

    assert <<45, 29, 152, 238, 71, 110, 105, 157, 247, 108, 42, 93, 248, 189, 247, 80, 104, 89,
             56, 213, 49, 194, 188, 134, 94, 37, 6, 101, 46, 12, 219,
             11>> == Keystore.diffie_hellman(pub)
  end

  property "node public key/0 should is equal to the previous one" do
    check all(nb_keys <- StreamData.positive_integer()) do
      KeystoreCounter.set_node_key_counter(nb_keys)
      assert Keystore.node_public_key(nb_keys - 1) == Keystore.node_public_key()
    end
  end

  property "node public key/1 should is not be equal to the previous one" do
    check all(nb_keys <- StreamData.positive_integer()) do
      KeystoreCounter.set_node_key_counter(nb_keys)

      assert Keystore.node_public_key(nb_keys - 1) !=
               Keystore.node_public_key(nb_keys)
    end
  end
end
