defmodule Archethic.TransactionChain.TransactionInputTest do
  use ExUnit.Case

  alias Archethic.Mining

  alias Archethic.TransactionChain.TransactionInput

  describe "serialization/deserialization workflow" do
    test "should return the same transaction after serialization and deserialization" do
      input = %TransactionInput{
        amount: 1,
        type: :UCO,
        from: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        reward?: true,
        spent?: true,
        timestamp: DateTime.utc_now()
      }

      protocol_version = Mining.protocol_version()

      assert input =
               TransactionInput.deserialize(
                 TransactionInput.serialize(input, protocol_version),
                 protocol_version
               )
    end
  end
end
