defmodule Archethic.SharedSecretsTest do
  use ExUnit.Case

  alias Archethic.{
    Crypto,
    SharedSecrets,
    SharedSecrets.MemTables.OriginKeyLookup
  }

  doctest SharedSecrets

  describe "has_origin_public_key?/1" do
    setup do
      start_supervised!(OriginKeyLookup)
      :ok
    end

    test "should return false when origin public key does not exist in Origin memtable" do
      {pb_key, _} = Crypto.derive_keypair("has_origin_public_key", 0)
      refute SharedSecrets.has_origin_public_key?(pb_key)
    end

    test "should return true when origin public key does not exist in Origin memtable" do
      {pb_key, _} = Crypto.derive_keypair("has_origin_public_key", 0)
      OriginKeyLookup.add_public_key(:software, pb_key)
      assert SharedSecrets.has_origin_public_key?(pb_key)
    end
  end
end
