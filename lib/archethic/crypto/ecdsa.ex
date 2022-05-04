defmodule Archethic.Crypto.ECDSA do
  @moduledoc false

  @type curve :: :secp256r1 | :secp256k1

  @curves [:secp256r1, :secp256k1]

  @doc """
  Generate an ECDSA keypair from a given secrets
  """
  @spec generate_keypair(curve(), binary()) :: {binary(), binary()}
  def generate_keypair(curve, seed)
      when curve in @curves and is_binary(seed) and byte_size(seed) < 32 do
    :crypto.generate_key(
      :ecdh,
      curve,
      :crypto.hash(:sha256, seed)
    )
  end

  def generate_keypair(curve, seed) when curve in @curves and is_binary(seed) do
    :crypto.generate_key(
      :ecdh,
      curve,
      :binary.part(seed, 0, 32)
    )
  end

  @doc """
  Sign a data with the given private key
  """
  @spec sign(curve(), binary(), iodata()) :: binary()
  def sign(curve, private_key, data)
      when curve in @curves and (is_binary(data) or is_list(data)) and is_binary(private_key) do
    :crypto.sign(:ecdsa, :sha256, data, [
      private_key,
      curve
    ])
  end

  @doc """
  Verify a signature using the given public key and data
  """
  @spec verify?(curve(), binary(), iodata(), binary()) :: boolean()
  def verify?(curve, public_key, data, sig)
      when curve in @curves and (is_binary(data) or is_list(data)) and is_binary(sig) do
    :crypto.verify(
      :ecdsa,
      :sha256,
      data,
      sig,
      [
        public_key,
        curve
      ]
    )
  end
end
