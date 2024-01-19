defmodule Archethic.TransactionChain.TransactionInputTest do
  use ArchethicCase

  alias Archethic.Mining
  alias Archethic.TransactionChain.TransactionInput
  doctest TransactionInput

  describe "serialization/deserialization workflow" do
    test "should return the same transaction after serialization and deserialization" do
      input = %TransactionInput{
        amount: 1,
        type: :UCO,
        from: ArchethicCase.random_address(),
        spent?: true,
        timestamp: DateTime.utc_now()
      }

      for protocol_version <- 1..Mining.protocol_version() do
        revised_input =
          if protocol_version < 6 do
            Map.update!(input, :timestamp, &DateTime.truncate(&1, :second))
          else
            Map.update!(input, :timestamp, &DateTime.truncate(&1, :millisecond))
          end

        assert {^revised_input, _} =
                 revised_input
                 |> TransactionInput.serialize(protocol_version)
                 |> TransactionInput.deserialize(protocol_version)
      end
    end
  end
end
