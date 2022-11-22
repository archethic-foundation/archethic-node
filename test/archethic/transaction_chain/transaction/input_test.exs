defmodule Archethic.TransactionChain.TransactionInputTest do
  use ArchethicCase

  import ArchethicCase, only: [current_protocol_version: 0]

  alias Archethic.Mining
  alias Archethic.TransactionChain.TransactionInput
  doctest TransactionInput

  describe "serialization/deserialization workflow" do
    test "should return the same transaction after serialization and deserialization" do
      input = %TransactionInput{
        amount: 1,
        type: :UCO,
        from: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        reward?: true,
        spent?: true,
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      protocol_version = Mining.protocol_version()

      assert {^input, _} =
               TransactionInput.deserialize(
                 TransactionInput.serialize(input, protocol_version),
                 protocol_version
               )
    end
  end
end
