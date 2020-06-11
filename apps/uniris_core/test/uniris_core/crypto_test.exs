defmodule UnirisCore.CryptoTest do
  use UnirisCoreCase, async: false
  doctest UnirisCore.Crypto
  use ExUnitProperties

  property "symmetric aes encryption and decryption" do
    check all(
            aes_key <- StreamData.binary(length: 32),
            data <- StreamData.binary()
          ) do
      cipher = UnirisCore.Crypto.aes_encrypt(data, aes_key)
      is_binary(cipher) and data == UnirisCore.Crypto.aes_decrypt!(cipher, aes_key)
    end
  end

  property "symmetric EC encryption and decryption" do
    check all(
            seed <- StreamData.binary(min_length: 1),
            data <- StreamData.binary(min_length: 1)
          ) do
      {pub, pv} = UnirisCore.Crypto.generate_deterministic_keypair(seed, :secp256r1)
      cipher = UnirisCore.Crypto.ec_encrypt(data, pub)
      is_binary(cipher) and data == UnirisCore.Crypto.ec_decrypt!(cipher, pv)
    end
  end

  property "symmetric EC encryption and decryption with Ed25519" do
    check all(
            seed <- StreamData.binary(min_length: 1),
            data <- StreamData.binary(min_length: 1)
          ) do
      {pub, pv} = UnirisCore.Crypto.generate_deterministic_keypair(seed, :ed25519)
      cipher = UnirisCore.Crypto.ec_encrypt(data, pub)
      is_binary(cipher) and data == UnirisCore.Crypto.ec_decrypt!(cipher, pv)
    end
  end
end
