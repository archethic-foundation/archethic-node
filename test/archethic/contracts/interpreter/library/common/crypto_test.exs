defmodule Archethic.Contracts.Interpreter.Library.Common.CryptoTest do
  @moduledoc """
  Here we test the module within the action block. Because there is AST modification (such as keywords to maps)
  in the ActionInterpreter and we want to test the whole thing.
  """

  use ArchethicCase

  alias Archethic.Contracts.Interpreter.Library.Common.Crypto

  doctest Crypto

  # ----------------------------------------
  describe "hash/1" do
    test "should work without algo" do
      text = "wu-tang"
      assert Crypto.hash(text) == Base.encode16(:crypto.hash(:sha256, text))
    end
  end

  describe "hash/2" do
    test "should work with algo" do
      text = "wu-tang"
      assert Crypto.hash(text, "sha512") == Base.encode16(:crypto.hash(:sha512, text))
    end

    test "should work with keccak256 for clear text" do
      text = "wu-tang"

      # Here directly use string to ensure ExKeccak dependency still works
      expected_hash = "CBB3D06AFFDADC9F6B5949E13AA7B06303731811452F61C6F3851F325CBE9D3E"

      assert ExKeccak.hash_256(text) |> Base.encode16() == expected_hash
      assert Crypto.hash(text, "keccak256") == expected_hash
    end

    test "should work with keccak256 for hexadecimal text" do
      hash = :crypto.hash(:sha256, "wu-tang")

      expected_hash = ExKeccak.hash_256(hash) |> Base.encode16()

      hex_hash = Base.encode16(hash)

      assert Crypto.hash(hex_hash, "keccak256") == expected_hash
    end
  end
end
