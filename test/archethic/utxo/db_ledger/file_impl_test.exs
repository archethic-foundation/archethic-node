defmodule Archethic.UTXO.DBLedger.FileImplTest do
  use ArchethicCase

  alias Archethic.UTXO.DBLedger.FileImpl, as: DBLedger
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  setup do
    DBLedger.setup_folder!()
    :ok
  end

  test "append/2 should add unspent output to the genesis file" do
    utxo = %VersionedUnspentOutput{
      protocol_version: ArchethicCase.current_protocol_version(),
      unspent_output: %UnspentOutput{
        from: ArchethicCase.random_address(),
        type: :UCO,
        amount: 100_000_000,
        timestamp: ~U[2023-05-10 00:10:00Z]
      }
    }

    assert :ok = DBLedger.append("@Alice0", utxo)
    assert File.exists?(DBLedger.file_path("@Alice0"))
  end

  describe "stream/1" do
    test "should retrieve all the unspent outputs for the genesis" do
      utxo1 = %VersionedUnspentOutput{
        protocol_version: ArchethicCase.current_protocol_version(),
        unspent_output: %UnspentOutput{
          from: ArchethicCase.random_address(),
          type: :UCO,
          amount: 100_000_000,
          timestamp: ~U[2023-05-10 00:10:00.000Z]
        }
      }

      assert :ok = DBLedger.append("@Alice0", utxo1)
      assert File.exists?(DBLedger.file_path("@Alice0"))

      utxo2 = %VersionedUnspentOutput{
        protocol_version: ArchethicCase.current_protocol_version(),
        unspent_output: %UnspentOutput{
          from: ArchethicCase.random_address(),
          type: :UCO,
          amount: 300_000_000,
          timestamp: ~U[2023-05-10 00:50:00.000Z]
        }
      }

      assert :ok = DBLedger.append("@Alice0", utxo2)

      assert [^utxo1, ^utxo2] =
               "@Alice0"
               |> DBLedger.stream()
               |> Enum.to_list()
    end

    test "should return empty list when the file doesn't exist" do
      assert DBLedger.stream("@Bob0") |> Enum.empty?()
    end
  end

  describe "flush/2" do
    test "should write all the unspent outputs to the file, erasing the previous ones" do
      utxo1 = %VersionedUnspentOutput{
        protocol_version: ArchethicCase.current_protocol_version(),
        unspent_output: %UnspentOutput{
          from: ArchethicCase.random_address(),
          type: :UCO,
          amount: 100_000_000,
          timestamp: ~U[2023-04-10 00:10:00.000Z]
        }
      }

      assert :ok = DBLedger.append("@Alice0", utxo1)
      assert File.exists?(DBLedger.file_path("@Alice0"))

      new_unspent_outputs = [
        %VersionedUnspentOutput{
          protocol_version: ArchethicCase.current_protocol_version(),
          unspent_output: %UnspentOutput{
            from: ArchethicCase.random_address(),
            type: :UCO,
            amount: 300_000_000,
            timestamp: ~U[2023-05-10 00:50:00.000Z]
          }
        },
        %VersionedUnspentOutput{
          protocol_version: ArchethicCase.current_protocol_version(),
          unspent_output: %UnspentOutput{
            from: ArchethicCase.random_address(),
            type: :state,
            encoded_payload: <<0, 1, 2, 3, 4>>,
            timestamp: ~U[2023-05-10 00:50:00.000Z]
          }
        }
      ]

      assert :ok = DBLedger.flush("@Alice0", new_unspent_outputs)

      assert ^new_unspent_outputs =
               "@Alice0"
               |> DBLedger.stream()
               |> Enum.to_list()
    end
  end
end
