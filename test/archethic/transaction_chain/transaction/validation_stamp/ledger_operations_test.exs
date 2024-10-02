defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperationsTest do
  alias Archethic.Reward.MemTables.RewardTokens

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  use ArchethicCase
  import ArchethicCase

  doctest LedgerOperations

  setup do
    start_supervised!(RewardTokens)
    :ok
  end

  describe "serialization" do
    test "should be able to serialize and deserialize" do
      ops = %LedgerOperations{
        fee: 10_000_000,
        transaction_movements: [
          %TransactionMovement{
            to:
              <<0, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
                86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
            amount: 102_000_000,
            type: :UCO
          }
        ],
        unspent_outputs: [
          %UnspentOutput{
            from:
              <<0, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
                86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
            amount: 200_000_000,
            type: :UCO,
            timestamp: ~U[2022-10-11 07:27:22.815Z]
          }
        ]
      }

      for version <- 1..current_protocol_version() do
        assert {^ops, <<>>} =
                 LedgerOperations.serialize(ops, version) |> LedgerOperations.deserialize(version)
      end
    end
  end

  describe "symmetric serialization" do
    test "should support latest protocol version" do
      ops = %LedgerOperations{
        fee: 10_000_000,
        transaction_movements: [
          %TransactionMovement{
            to:
              <<0, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
                86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
            amount: 1_020_000_000,
            type: :UCO
          }
        ],
        unspent_outputs: [
          %UnspentOutput{
            from:
              <<0, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
                86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
            amount: 200_000_000,
            type: :UCO,
            timestamp: ~U[2022-10-11 07:27:22.815Z]
          }
        ],
        consumed_inputs: [
          %UnspentOutput{
            from:
              <<0, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
                86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
            amount: 200_000_000,
            type: :UCO,
            timestamp: ~U[2022-10-11 07:27:22.815Z]
          }
          |> VersionedUnspentOutput.wrap_unspent_output(current_protocol_version())
        ]
      }

      assert ops ==
               ops
               |> LedgerOperations.serialize(current_protocol_version())
               |> LedgerOperations.deserialize(current_protocol_version())
               |> elem(0)
    end

    test "should support backward compatible" do
      ops = %LedgerOperations{
        fee: 10_000_000,
        transaction_movements: [
          %TransactionMovement{
            to:
              <<0, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
                86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
            amount: 1_020_000_000,
            type: :UCO
          }
        ],
        unspent_outputs: [
          %UnspentOutput{
            from:
              <<0, 0, 34, 118, 242, 194, 93, 131, 130, 195, 9, 97, 237, 220, 195, 112, 1, 54, 221,
                86, 154, 234, 96, 217, 149, 84, 188, 63, 242, 166, 47, 158, 139, 207>>,
            amount: 200_000_000,
            type: :UCO,
            timestamp: ~U[2022-10-11 07:27:22.815Z]
          }
        ]
      }

      assert ops ==
               ops
               |> LedgerOperations.serialize(1)
               |> LedgerOperations.deserialize(1)
               |> elem(0)
    end
  end
end
