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

    assert <<152, 14, 126, 184, 29, 146, 12, 190, 178, 52, 89, 38, 226, 22, 94, 92, 51, 235, 170,
             77, 41, 188, 203, 171, 250, 240, 84, 234, 36, 109, 239,
             120>> == Keystore.diffie_hellman(pub)
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
