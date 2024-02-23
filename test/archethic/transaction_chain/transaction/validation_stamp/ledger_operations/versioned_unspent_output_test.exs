defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutputTest do
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.Utils

  use ArchethicCase
  import ArchethicCase

  doctest VersionedUnspentOutput

  describe "hash/1" do
    test "should return the same hash (32B) for the same utxo" do
      timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)
      token_address = random_address()
      from_address = random_address()

      utxo = %UnspentOutput{
        amount: Utils.to_bigint(1000),
        type: {:token, token_address, 0},
        from: from_address,
        timestamp: timestamp
      }

      expected_hash =
        utxo
        |> VersionedUnspentOutput.wrap_unspent_output(current_protocol_version())
        |> VersionedUnspentOutput.hash()

      assert 32 = byte_size(expected_hash)

      assert ^expected_hash =
               utxo
               |> VersionedUnspentOutput.wrap_unspent_output(current_protocol_version())
               |> VersionedUnspentOutput.hash()
    end

    test "should return different hashes (32B) for the different utxo" do
      timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)
      token_address = random_address()
      from_address = random_address()

      utxo1 =
        %UnspentOutput{
          amount: Utils.to_bigint(1000),
          type: {:token, token_address, 0},
          from: from_address,
          timestamp: timestamp
        }
        |> VersionedUnspentOutput.wrap_unspent_output(current_protocol_version())

      utxo2 =
        %UnspentOutput{
          amount: Utils.to_bigint(100),
          type: {:token, token_address, 0},
          from: from_address,
          timestamp: timestamp
        }
        |> VersionedUnspentOutput.wrap_unspent_output(current_protocol_version())

      assert VersionedUnspentOutput.hash(utxo1) != VersionedUnspentOutput.hash(utxo2)
    end
  end
end
