defmodule Uniris.Crypto.Ed25519 do
  alias Uniris.Crypto.LibSodiumPort

  @moduledoc false

  def generate_keypair(private_key) when byte_size(private_key) < 32 do
    right_padding = Enum.map(1..(32 - byte_size(private_key)), fn _ -> <<0>> end)

    :crypto.generate_key(
      :eddsa,
      :ed25519,
      [private_key, right_padding] |> :erlang.list_to_binary()
    )
  end

  def generate_keypair(<<private_key::binary-32, _::binary>>) do
    :crypto.generate_key(:eddsa, :ed25519, private_key)
  end

  def encrypt(_key = <<public_key::binary-32>>, data) do
    {:ok, cipher} = GenServer.call(LibSodiumPort, {:encrypt, public_key, data})
    cipher
  end

  def decrypt(_key = <<private_key::binary-32>>, data) do
    {pub, pv} = :crypto.generate_key(:eddsa, :ed25519, private_key)

    case GenServer.call(LibSodiumPort, {:decrypt, <<pv::binary, pub::binary>>, data}) do
      {:ok, data} ->
        data

      _ ->
        raise "Decryption failed"
    end
  end

  def sign(_key = <<private_key::binary-32>>, data) do
    :crypto.sign(:eddsa, :sha512, :crypto.hash(:sha512, data), [private_key, :ed25519])
  end

  def verify(<<public_key::binary-32>>, data, sig) do
    :crypto.verify(:eddsa, :sha512, :crypto.hash(:sha512, data), sig, [public_key, :ed25519])
  end
end
