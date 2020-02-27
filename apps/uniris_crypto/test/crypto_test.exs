defmodule CryptoTest do
  use ExUnit.Case
  alias UnirisCrypto, as: Crypto

  doctest Crypto

  describe "random generation of keys" do

    test "should return a keypair when using an ECDSA curve" do
      <<1::8, pub_key::binary>> = Crypto.generate_random_keypair(curve: :secp256r1)

      assert byte_size(pub_key) == 65
    end

    test "should return a keypair when using ed25519" do
      <<0::8, pub_key::binary>> = Crypto.generate_random_keypair(curve: :ed25519)

      assert byte_size(pub_key) == 32
    end
  end

  describe "ECIES encryption" do
    test "should return authenticated encrypted when using ECDSA key" do
      pub = Crypto.generate_random_keypair(curve: :secp256r1)

      assert match?(
               <<_rand_pub_key::8*65, _tag::8*16, _cipher::binary>>,
               Crypto.ec_encrypt("hello", pub)
             )
    end

    test "should return authenticated encrypted data when using Ed25519 key" do
      pub = Crypto.generate_random_keypair(curve: :ed25519)
      cipher = Crypto.ec_encrypt("hello", pub)
      assert is_binary(cipher)
    end
  end
end
