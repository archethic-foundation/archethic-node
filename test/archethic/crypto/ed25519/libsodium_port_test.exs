defmodule Archethic.Crypto.Ed25519.LibSodiumPortTest do
  use ExUnit.Case

  alias Archethic.Crypto.Ed25519.LibSodiumPort

  setup do
    LibSodiumPort.start_link()
    :ok
  end

  test "convert_public_key_to_x25519/1 should convert a ed25519 public into a x25519 public key" do
    seed =
      <<71, 35, 126, 230, 163, 84, 90, 215, 215, 23, 244, 30, 11, 130, 234, 119, 150, 24, 203,
        125, 60, 53, 109, 214, 11, 225, 110, 226, 168, 103, 64, 90>>

    {pub, _} = :crypto.generate_key(:eddsa, :ed25519, seed)

    assert {:ok,
            <<115, 197, 215, 64, 38, 160, 186, 251, 140, 192, 237, 237, 57, 133, 110, 153, 40,
              154, 251, 163, 56, 34, 41, 243, 234, 148, 121, 108, 19, 249, 56,
              50>>} = LibSodiumPort.convert_public_key_to_x25519(pub)
  end

  test "convert_secret_key_to_x25519/1 should convert a ed25519 secret key into a x25519 secret key" do
    seed =
      <<71, 35, 126, 230, 163, 84, 90, 215, 215, 23, 244, 30, 11, 130, 234, 119, 150, 24, 203,
        125, 60, 53, 109, 214, 11, 225, 110, 226, 168, 103, 64, 90>>

    {pub, pv} = :crypto.generate_key(:eddsa, :ed25519, seed)

    assert {:ok,
            <<16, 8, 228, 130, 220, 80, 188, 110, 230, 36, 43, 253, 135, 246, 135, 25, 14, 144,
              217, 162, 196, 123, 69, 88, 113, 237, 117, 246, 83, 193, 235,
              94>>} = LibSodiumPort.convert_secret_key_to_x25519(<<pub::binary, pv::binary>>)
  end
end
