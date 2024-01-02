defmodule Archethic.TransactionChain.TransactionSummaryTest do
  use ExUnit.Case

  alias Archethic.TransactionChain.TransactionSummary

  describe "serialize/deserialize" do
    test "should encode transaction summary in version 1" do
      tx_summary = %TransactionSummary{
        address: ArchethicCase.random_address(),
        timestamp: ~U[2020-06-25 15:11:53.000Z],
        type: :transfer,
        movements_addresses: [ArchethicCase.random_address()],
        fee: 10_000_000,
        validation_stamp_checksum: :crypto.strong_rand_bytes(32),
        version: 1
      }

      assert {^tx_summary, <<>>} =
               tx_summary
               |> TransactionSummary.serialize()
               |> TransactionSummary.deserialize()
    end

    test "should encode transaction summary in latest version" do
      tx_summary = %TransactionSummary{
        address: ArchethicCase.random_address(),
        timestamp: ~U[2020-06-25 15:11:53.000Z],
        type: :transfer,
        movements_addresses: [ArchethicCase.random_address()],
        fee: 10_000_000,
        validation_stamp_checksum: :crypto.strong_rand_bytes(32),
        genesis_address: ArchethicCase.random_address()
      }

      assert {^tx_summary, <<>>} =
               tx_summary
               |> TransactionSummary.serialize()
               |> TransactionSummary.deserialize()
    end
  end
end
