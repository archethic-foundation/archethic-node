defmodule Archethic.Account.GenesisStateTest do
  use ArchethicCase

  alias Archethic.Account.GenesisState
  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.VersionedTransactionInput

  setup do
    File.mkdir_p!(GenesisState.base_path())
    :ok
  end

  test "persist/2 should write the genesis state on disk" do
    unspent_outputs = [
      %VersionedTransactionInput{
        protocol_version: 1,
        input: %TransactionInput{
          from: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          type: :UCO,
          amount: 300_000_000,
          timestamp: ~U[2023-05-10 00:10:00Z]
        }
      },
      %VersionedTransactionInput{
        protocol_version: 1,
        input: %TransactionInput{
          from: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          type: {:token, <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>, 0},
          amount: 100_000_000,
          timestamp: ~U[2023-05-10 00:50:00Z]
        }
      }
    ]

    assert :ok = GenesisState.persist("@Alice2", unspent_outputs)
    assert File.exists?(GenesisState.file_path("@Alice2"))
  end

  describe "fetch/1" do
    test "should fetch persisted list of unspent outputs when the file exists" do
      unspent_outputs = [
        %VersionedTransactionInput{
          protocol_version: 1,
          input: %TransactionInput{
            from: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
            type: :UCO,
            amount: 300_000_000,
            timestamp: ~U[2023-05-10 00:10:00Z]
          }
        },
        %VersionedTransactionInput{
          protocol_version: 1,
          input: %TransactionInput{
            from: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
            type: {:token, <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>, 0},
            amount: 100_000_000,
            timestamp: ~U[2023-05-10 00:50:00Z]
          }
        }
      ]

      assert :ok = GenesisState.persist("@Alice2", unspent_outputs)
      assert ^unspent_outputs = GenesisState.fetch("@Alice2")
    end

    test "should return empty list when the file doesn't exists" do
      assert [] == GenesisState.fetch("@Bob5")
    end
  end
end
