defmodule Archethic.Account.GenesisPendingLogTest do
  use ArchethicCase

  alias Archethic.Account.GenesisPendingLog
  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.TransactionChain.TransactionInput

  setup do
    File.mkdir_p!(GenesisPendingLog.base_path())
    :ok
  end

  test "append/2 should add input to the pending log file" do
    input = %VersionedTransactionInput{
      protocol_version: 1,
      input: %TransactionInput{
        from: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        type: :UCO,
        amount: 100_000_000,
        timestamp: ~U[2023-05-10 00:10:00Z]
      }
    }

    assert :ok = GenesisPendingLog.append("@Alice2", input)
    assert File.exists?(GenesisPendingLog.file_path("@Alice2"))
  end

  describe "fetch/1" do
    test "should retrieve all the inputs serialized" do
      input1 = %VersionedTransactionInput{
        protocol_version: 1,
        input: %TransactionInput{
          from: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          type: :UCO,
          amount: 100_000_000,
          timestamp: ~U[2023-05-10 00:10:00Z]
        }
      }

      assert :ok = GenesisPendingLog.append("@Alice2", input1)
      assert File.exists?(GenesisPendingLog.file_path("@Alice2"))

      input2 = %VersionedTransactionInput{
        protocol_version: 1,
        input: %TransactionInput{
          from: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          type: :UCO,
          amount: 300_000_000,
          timestamp: ~U[2023-05-10 00:50:00Z]
        }
      }

      assert :ok = GenesisPendingLog.append("@Alice2", input2)

      assert [^input1, ^input2] =
               "@Alice2"
               |> GenesisPendingLog.stream()
               |> Enum.to_list()
    end

    test "should return empty list when the file doesn't exists" do
      assert GenesisPendingLog.stream("@Bob3") |> Enum.empty?()
    end
  end

  test "clear/1 should delete the log file" do
    input = %VersionedTransactionInput{
      protocol_version: 1,
      input: %TransactionInput{
        from: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        type: :UCO,
        amount: 100_000_000,
        timestamp: ~U[2023-05-10 00:10:00Z]
      }
    }

    assert :ok = GenesisPendingLog.append("@Alice2", input)
    assert File.exists?(GenesisPendingLog.file_path("@Alice2"))

    GenesisPendingLog.clear("@Alice2")
    refute File.exists?(GenesisPendingLog.file_path("@Alice2"))
  end
end
