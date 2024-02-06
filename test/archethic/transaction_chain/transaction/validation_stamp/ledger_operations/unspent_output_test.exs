defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutputTest do
  alias Archethic.Mining
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.Utils

  use ArchethicCase
  import ArchethicCase

  doctest UnspentOutput

  describe "hash/1" do
    test "should return the same hash (32B) for the same utxo" do
      timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)
      token_address = random_address()
      from_address = random_address()

      expected_hash =
        UnspentOutput.hash(%UnspentOutput{
          amount: Utils.to_bigint(1000),
          type: {:token, token_address, 0},
          from: from_address,
          timestamp: timestamp
        })

      assert ^expected_hash =
               UnspentOutput.hash(%UnspentOutput{
                 amount: Utils.to_bigint(1000),
                 type: {:token, token_address, 0},
                 from: from_address,
                 timestamp: timestamp
               })

      assert 32 = byte_size(expected_hash)
    end

    test "should return different hashes (32B) for the different utxo" do
      timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)
      token_address = random_address()
      from_address = random_address()

      utxo1 = %UnspentOutput{
        amount: Utils.to_bigint(1000),
        type: {:token, token_address, 0},
        from: from_address,
        timestamp: timestamp
      }

      utxo2 = %UnspentOutput{
        amount: Utils.to_bigint(100),
        type: {:token, token_address, 0},
        from: from_address,
        timestamp: timestamp
      }

      assert UnspentOutput.hash(utxo1) != UnspentOutput.hash(utxo2)
    end
  end

  describe "serialization/deserialization workflow" do
    test "should work for :uco/:token in all protocol version" do
      for version <- 1..Mining.protocol_version() do
        do_test_uco_token(version)
      end
    end

    test "should work for :state in protocol version 4+ < 6" do
      # state (introduced in v4)
      input = %UnspentOutput{
        type: :state,
        encoded_payload: :crypto.strong_rand_bytes(10)
      }

      for protocol_version <- 4..6 do
        assert {^input, _} =
                 UnspentOutput.deserialize(
                   UnspentOutput.serialize(input, protocol_version),
                   protocol_version
                 )
      end
    end

    test "should work for :state in protocol version 6+" do
      for protocol_version <- 7..Mining.protocol_version() do
        do_test_state(protocol_version)
      end
    end
  end

  defp do_test_state(protocol_version) do
    # state (introduced in v5)
    input = %UnspentOutput{
      type: :state,
      from: random_address(),
      timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond),
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
