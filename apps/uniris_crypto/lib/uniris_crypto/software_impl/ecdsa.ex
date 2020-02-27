defmodule UnirisCrypto.SoftwareImpl.ECDSA do
  @moduledoc false

  def generate_keypair(curve) do
    :crypto.generate_key(:ecdh, curve)
  end

  def generate_keypair(seed, curve) do
    :crypto.generate_key(:ecdh, curve, seed)
  end

  def sign(private_key, curve, data) do
    :crypto.sign(:ecdsa, :sha256, :crypto.hash(:sha256, data), [
      private_key,
      curve
    ])
  end

  def verify(public_key, curve, data, sig) do
    :crypto.verify(
      :ecdsa,
      :sha256,
      :crypto.hash(:sha256, data),
      sig,
      [
        public_key,
        curve
      ]
    )
  end

  def encrypt(public_key, curve, message) do
    with {ephemeral_public_key, <<_::8, ephemeral_private_key::binary>>} <-
           generate_keypair(curve) do
      # Derivate secret using ECDH with the given public key and the ephemeral private key
      shared_key = generate_dh_key(curve, public_key, ephemeral_private_key)

      # Generate keys for the AES authenticated encryption
      {iv, aes_key} = derivate_secrets(shared_key)

      {cipher, tag} = aes_auth_encrypt(iv, aes_key, message)

      # Encode the cipher within the ephemeral public key, the authentication tag
      ephemeral_public_key <> tag <> cipher
    end
  end

  def decrypt(
        private_key,
        curve,
        _encoded_cipher = <<_::8, ephemeral_public_key::8*65, tag::8*16, cipher::binary>>
      ) do
    ephemeral_public_key = :binary.encode_unsigned(ephemeral_public_key)
    tag = :binary.encode_unsigned(tag)

    # Derivate shared key using ECDH with the given ephermal public key and the private key
    shared_key = generate_dh_key(curve, ephemeral_public_key, private_key)

    # Generate keys for the AES authenticated decryption
    {iv, aes_key} = derivate_secrets(shared_key)

    case aes_auth_decrypt(iv, aes_key, cipher, tag) do
      :error ->
        raise "Decryption failed"

      data ->
        data
    end
  end

  defp generate_dh_key(curve, public_key, private_key),
    do: :crypto.compute_key(:ecdh, public_key, private_key, curve)

  defp derivate_secrets(dh_key) do
    pseudorandom_key = :crypto.hmac(:sha256, "", dh_key)
    iv = binary_part(:crypto.hmac(:sha256, pseudorandom_key, "0"), 0, 32)
    aes_key = binary_part(:crypto.hmac(:sha256, iv, "1"), 0, 32)
    {iv, aes_key}
  end

  defp aes_auth_encrypt(iv, key, data),
    do: :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, data, "", true)

  defp aes_auth_decrypt(iv, key, cipher, tag),
    do: :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, cipher, "", tag, false)
end
