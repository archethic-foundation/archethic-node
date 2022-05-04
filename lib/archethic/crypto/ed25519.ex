defmodule Archethic.Crypto.Ed25519 do
  @moduledoc false

  alias __MODULE__.LibSodiumPort

  @doc """
  Generate an Ed25519 key pair
  """
  @spec generate_keypair(binary()) :: {binary(), binary()}
  def generate_keypair(seed) when is_binary(seed) and byte_size(seed) < 32 do
    seed = :crypto.hash(:sha256, seed)
    do_generate_keypair(seed)
  end

  def generate_keypair(seed) when is_binary(seed) and byte_size(seed) > 32 do
    do_generate_keypair(:binary.part(seed, 0, 32))
  end

  def generate_keypair(seed) when is_binary(seed) do
    do_generate_keypair(seed)
  end

  defp do_generate_keypair(seed) do
    :crypto.generate_key(
      :eddsa,
      :ed25519,
      seed
    )
  end

  @doc """
  Convert a ed25519 public key into a x25519
  """
  @spec convert_to_x25519_public_key(binary()) :: binary()
  def convert_to_x25519_public_key(ed25519_public_key) do
    {:ok, x25519_pub} = LibSodiumPort.convert_public_key_to_x25519(ed25519_public_key)
    x25519_pub
  end

  @doc """
  Convert a ed25519 secret key into a x25519
  """
  @spec convert_to_x25519_private_key(binary()) :: binary()
  def convert_to_x25519_private_key(ed25519_private_key) do
    {pub, pv} = generate_keypair(ed25519_private_key)
    extended_secret_key = <<pv::binary, pub::binary>>
    {:ok, x25519_pv} = LibSodiumPort.convert_secret_key_to_x25519(extended_secret_key)
    x25519_pv
  end

  @doc """
  Sign a message with the given Ed25519 private key
  """
  @spec sign(binary(), iodata()) :: binary()
  def sign(_key = <<private_key::binary-32>>, data) when is_binary(data) or is_list(data) do
    :crypto.sign(:eddsa, :sha512, data, [private_key, :ed25519])
  end

  @doc """
  Verify if a given Ed25519 public key matches the signature among with its data
  """
  @spec verify?(binary(), binary(), binary()) :: boolean()
  def verify?(<<public_key::binary-32>>, data, sig)
      when (is_binary(data) or is_list(data)) and is_binary(sig) do
    :crypto.verify(:eddsa, :sha512, data, sig, [public_key, :ed25519])
  end
end
