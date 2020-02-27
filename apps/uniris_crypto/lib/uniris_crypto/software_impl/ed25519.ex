defmodule UnirisCrypto.SoftwareImpl.Ed25519 do
  @moduledoc false

  alias UnirisCrypto.SoftwareImpl.LibSodiumPort, as: Ed25519Port

  def generate_keypair() do
    {:ok, <<secret_key::binary-64, public_key::binary-32>>} =
      GenServer.call(Ed25519Port, :generate_key)

    {public_key, secret_key}
  end

  def generate_keypair(seed)
      when byte_size(seed) < 32 and byte_size(seed) > 0,
      do:
        generate_keypair(
          Enum.reduce(1..(32 - byte_size(seed)), seed, fn _, acc -> acc <> <<0>> end)
        )

  def generate_keypair(<<seed::binary-32, _::binary>>) do
    {:ok, <<secret_key::binary-64, public_key::binary-32>>} =
      GenServer.call(Ed25519Port, {:generate_key, seed})

    {public_key, secret_key}
  end

  def encrypt(<<public_key::binary-32>> = _key, data) do
    {:ok, cipher} = GenServer.call(Ed25519Port, {:encrypt, public_key, data})
    cipher
  end

  def decrypt(<<secret_key::binary-64>> = _key, data) do
    case GenServer.call(Ed25519Port, {:decrypt, secret_key, data}) do
      {:ok, data} ->
        data

      _ ->
        raise "Decryption failed"
    end
  end

  def sign(<<secret_key::binary-64>> = _key, data) do
    {:ok, sig} = GenServer.call(Ed25519Port, {:sign, secret_key, data})
    sig
  end

  def verify(<<public_key::binary-32>>, data, sig) do
    if byte_size(sig) != 64 do
      false
    else
      case GenServer.call(Ed25519Port, {:verify, public_key, data, sig}) do
        :ok ->
          true

        {:error, :invalid_signature} ->
          false
      end
    end
  end
end
