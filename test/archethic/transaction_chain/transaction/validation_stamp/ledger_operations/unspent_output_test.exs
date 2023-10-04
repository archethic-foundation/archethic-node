defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutputTest do
  alias Archethic.Mining
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.Utils

  use ArchethicCase
  import ArchethicCase

  doctest UnspentOutput

  describe "serialization/deserialization workflow" do
    test "should work for :uco/:token in all protocol version" do
      for version <- 1..Mining.protocol_version() do
        do_test_uco_token(version)
      end
    end

    test "should work for :state in protocol version 4+" do
      for version <- 4..Mining.protocol_version() do
        do_test_state(version)
      end
    end
  end

  defp do_test_state(protocol_version) do
    # state (introduced in v4)
    input = %UnspentOutput{
      type: :state,
      encoded_payload: :crypto.strong_rand_bytes(10)
    }

    assert {^input, _} =
             UnspentOutput.deserialize(
               UnspentOutput.serialize(input, protocol_version),
               protocol_version
             )
  end

  defp do_test_uco_token(protocol_version) do
    # uco
    input = %UnspentOutput{
      amount: Utils.to_bigint(130),
      type: :UCO,
      from: random_address(),
      timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
    }

    assert {^input, _} =
             UnspentOutput.deserialize(
               UnspentOutput.serialize(input, protocol_version),
               protocol_version
             )

    # token
    input = %UnspentOutput{
      amount: Utils.to_bigint(1000),
      type: {:token, random_address(), 0},
      from: random_address(),
      timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
    }

    assert {^input, _} =
             UnspentOutput.deserialize(
               UnspentOutput.serialize(input, protocol_version),
               protocol_version
             )
  end
end
