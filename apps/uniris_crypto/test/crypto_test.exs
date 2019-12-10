defmodule CryptoTest do
  use ExUnit.Case
  alias UnirisCrypto, as: Crypto

  doctest Crypto

  describe "random generation of keys" do
    test "should fail with an unsupported curve" do
      assert {:error, :invalid_curve} = Crypto.generate_random_keypair(curve: :fake_curve)
    end

    test "should return a keypair when using an ECDSA curve" do
      {:ok, <<1::8, pub_key::binary>>} = Crypto.generate_random_keypair(curve: :secp256r1)

      assert byte_size(pub_key) == 65
    end

    test "should return a keypair when using ed25519" do
      {:ok, <<0::8, pub_key::binary>>} = Crypto.generate_random_keypair(curve: :ed25519)

      assert byte_size(pub_key) == 32
    end
  end

  describe "ECIES encryption" do
    test "should failed with an invalid public key" do
      assert {:error, :invalid_key} = Crypto.ec_encrypt("hello", :crypto.strong_rand_bytes(32))
    end

    test "should return authenticated encrypted when using ECDSA key" do
      {:ok, pub} = Crypto.generate_random_keypair(curve: :secp256r1)

      assert match?(
               {:ok, <<_rand_pub_key::8*65, _tag::8*16, _cipher::binary>>},
               Crypto.ec_encrypt("hello", pub)
             )
    end

    test "should return authenticated encrypted data when using Ed25519 key" do
      {:ok, pub} = Crypto.generate_random_keypair(curve: :ed25519)
      {:ok, cipher} = Crypto.ec_encrypt("hello", pub)
      assert is_binary(cipher)
    end
  end
end
