defmodule UnirisCrypto.Ed25519 do
  @moduledoc false

  def generate_keypair(seed)
      when byte_size(seed) < 32 and byte_size(seed) > 0,
      do:
        generate_keypair(
          Enum.reduce(1..(32 - byte_size(seed)), seed, fn _, acc -> acc <> <<0>> end)
        )

  def generate_keypair(<<seed::binary-32, _::binary>>) do
    {:ok, <<secret_key::binary-64, public_key::binary-32>>} =
      :poolboy.transaction(
        :libsodium,
        fn pid -> GenServer.call(pid, {:generate_key, seed}) end
      )

    {public_key, secret_key}
  end

  def encrypt(<<public_key::binary-32>> = _key, data) do
    {:ok, cipher} =
      :poolboy.transaction(
        :libsodium,
        fn pid -> GenServer.call(pid, {:encrypt, public_key, data}) end
      )

    cipher
  end

  def decrypt(<<secret_key::binary-64>> = _key, data) do
    case :poolboy.transaction(
           :libsodium,
           fn pid -> GenServer.call(pid, {:decrypt, secret_key, data}) end
         ) do
      {:ok, data} ->
        data

      _ ->
        raise "Decryption failed"
    end
  end

  def sign(<<secret_key::binary-64>> = _key, data) do
    {:ok, sig} =
      :poolboy.transaction(
        :libsodium,
        fn pid -> GenServer.call(pid, {:sign, secret_key, data}) end
      )

    sig
  end

  def verify(<<public_key::binary-32>>, data, sig) do
    if byte_size(sig) != 64 do
      false
    else
      case :poolboy.transaction(
             :libsodium,
             fn pid -> GenServer.call(pid, {:verify, public_key, data, sig}) end
           ) do
        :ok ->
          true

        {:error, :invalid_signature} ->
          false
      end
    end
  end
end
