defmodule UnirisCrypto.SoftwareImpl.Ed25519 do
  @moduledoc false

  alias UnirisCrypto.SoftwareImpl.LibSodiumPort, as: Ed25519Port
  require Logger

  def generate_keypair() do
    with {:ok, keypair} <- GenServer.call(Ed25519Port, :generate_key) do
      secret_key = binary_part(keypair, 0, 64)
      public_key = binary_part(keypair, 64, 32)
      {:ok, public_key, secret_key}
    end
  end

  def generate_keypair(seed)
      when is_binary(seed) and byte_size(seed) < 32 and byte_size(seed) > 0,
      do:
        generate_keypair(
          Enum.reduce(1..(32 - byte_size(seed)), seed, fn _, acc -> acc <> <<0>> end)
        )

  def generate_keypair(<<seed::binary-32, _::binary>>) do
    with {:ok, keypair} <- GenServer.call(Ed25519Port, {:generate_key, seed}) do
      secret_key = binary_part(keypair, 0, 64)
      public_key = binary_part(keypair, 64, 32)
      {:ok, public_key, secret_key}
    end
  end

  def encrypt(<<public_key::binary-32>> = _key, data) when is_binary(data) do
    GenServer.call(Ed25519Port, {:encrypt, public_key, data})
  end

  def decrypt(<<secret_key::binary-64>> = _key, data) when is_binary(data) do
    with {:ok, data} <- GenServer.call(Ed25519Port, {:decrypt, secret_key, data}) do
      {:ok, data}
    else
      _ ->
        {:error, :decryption_failed}
    end
  end

  def sign(<<secret_key::binary-64>> = _key, data) when is_binary(data) do
    GenServer.call(Ed25519Port, {:sign, secret_key, data})
  end

  def verify(<<public_key::binary-32>>, data, sig) when is_binary(data) and is_binary(sig) do
    if byte_size(sig) != 64 do
      {:error, :invalid_signature}
    else
      case GenServer.call(Ed25519Port, {:verify, public_key, data, sig}) do
        :ok ->
          :ok

        {:error, :missing_signature} ->
          {:error, :invalid_signature}

        {:error, :invalid_signature} ->
          {:error, :invalid_signature}
      end
    end
  end
end
