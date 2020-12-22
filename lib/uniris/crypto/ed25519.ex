defmodule Uniris.Crypto.Ed25519 do
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
  Encrypt a message using the given Ed25519 public key
  """
  @spec encrypt(binary(), binary()) :: binary()
  def encrypt(_key = <<public_key::binary-32>>, data) do
    {:ok, <<_cipher_length::32, cipher::binary>>} =
      GenServer.call(LibSodiumPort, {:encrypt, public_key, data})

    cipher
  end

  @doc """
  Decrypt a message with the given Ed25519 private key

  Raise if the decryption failed
  """
  @spec decrypt(binary(), binary()) :: binary()
  def decrypt(_key = <<private_key::binary-32>>, data) when is_binary(data) do
    {pub, pv} = :crypto.generate_key(:eddsa, :ed25519, private_key)

    case GenServer.call(LibSodiumPort, {:decrypt, <<pv::binary, pub::binary>>, data}) do
      {:ok, data} ->
        data

      _ ->
        raise "Decryption failed"
    end
  end

  @doc """
  Sign a message with the given Ed25519 private key
  """
  @spec sign(binary(), iodata()) :: binary()
  def sign(_key = <<private_key::binary-32>>, data) when is_binary(data) or is_list(data) do
    :crypto.sign(:eddsa, :sha512, :crypto.hash(:sha512, data), [private_key, :ed25519])
  end

  @doc """
  Verify if a given Ed25519 public key matches the signature among with its data
  """
  @spec verify(binary(), binary(), binary()) :: boolean()
  def verify(<<public_key::binary-32>>, data, sig)
      when (is_binary(data) or is_list(data)) and is_binary(sig) do
    :crypto.verify(:eddsa, :sha512, :crypto.hash(:sha512, data), sig, [public_key, :ed25519])
  end
end
