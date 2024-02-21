defmodule Archethic.TransactionChain.Transaction.ValidationStampTest do
  use ArchethicCase

  import ArchethicCase, only: [current_protocol_version: 0]
  use ExUnitProperties

  alias Archethic.Crypto

  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  doctest ValidationStamp

  property "symmetric sign/valid validation stamp" do
    check all(
            proof_of_work <- StreamData.binary(length: 33),
            proof_of_integrity <- StreamData.binary(length: 33),
            proof_of_election <- StreamData.binary(length: 32),
            ledger_operations <- gen_ledger_operations()
          ) do
      pub = Crypto.last_node_public_key()

      assert %ValidationStamp{
               timestamp: DateTime.utc_now(),
               proof_of_work: proof_of_work,
               proof_of_integrity: proof_of_integrity,
               proof_of_election: proof_of_election,
               ledger_operations: ledger_operations,
               protocol_version: current_protocol_version()
             }
             |> ValidationStamp.sign()
             |> ValidationStamp.valid_signature?(pub)
    end
  end

  defp gen_ledger_operations do
    gen all(
          fee <- StreamData.positive_integer(),
          transaction_movements <- StreamData.list_of(gen_transaction_movement()),
          unspent_outputs <- StreamData.list_of(gen_unspent_outputs())
        ) do
      %LedgerOperations{
        fee: fee,
        transaction_movements: transaction_movements,
        unspent_outputs: unspent_outputs
      }
    end
  end

  defp gen_transaction_movement do
    gen all(
          to <- StreamData.binary(length: 33),
          amount <- StreamData.positive_integer(),
          type <-
            StreamData.one_of([
              StreamData.constant(:UCO),
              StreamData.tuple(
                {StreamData.constant(:token), StreamData.binary(length: 33),
                 StreamData.positive_integer()}
              )
            ])
        ) do
      %TransactionMovement{to: to, amount: amount, type: type}
    end
  end

  defp gen_unspent_outputs do
    gen all(
          from <- StreamData.binary(length: 33),
          amount <- StreamData.positive_integer(),
          timestamp <- StreamData.constant(DateTime.utc_now() |> DateTime.truncate(:millisecond)),
          type <-
            StreamData.one_of([
              StreamData.constant(:UCO),
              StreamData.tuple(
                {StreamData.constant(:token), StreamData.binary(length: 33),
                 StreamData.positive_integer()}
              )
            ])
        ) do
      %UnspentOutput{from: from, amount: amount, type: type, timestamp: timestamp}
    end
  end

  describe "symmetric serialization" do
    test "should support latest version" do
      stamp = %ValidationStamp{
        timestamp: ~U[2021-05-07 13:11:19.000Z],
        proof_of_work:
          <<0, 0, 34, 248, 200, 166, 69, 102, 246, 46, 84, 7, 6, 84, 66, 27, 8, 78, 103, 37, 155,
            114, 208, 205, 40, 44, 6, 159, 178, 5, 186, 168, 237, 206>>,
        proof_of_integrity:
          <<0, 49, 174, 251, 208, 41, 135, 147, 199, 114, 232, 140, 254, 103, 186, 138, 175, 28,
            156, 201, 30, 100, 75, 172, 95, 135, 167, 180, 242, 16, 74, 87, 170>>,
        proof_of_election:
          <<195, 51, 61, 55, 140, 12, 138, 246, 249, 106, 198, 175, 145, 9, 255, 133, 67, 240,
            175, 53, 236, 65, 151, 191, 128, 11, 58, 103, 82, 6, 218, 31, 220, 114, 65, 3, 151,
            209, 9, 84, 209, 105, 191, 180, 156, 157, 95, 25, 202, 2, 169, 112, 109, 54, 99, 40,
            47, 96, 93, 33, 82, 40, 100, 13>>,
        ledger_operations: %LedgerOperations{
          fee: 10_000_000,
          transaction_movements: [],
          unspent_outputs: [],
          consumed_inputs: [
            %UnspentOutput{
              from:
                <<0, 0, 173, 169, 83, 136, 99, 24, 144, 188, 36, 180, 147, 166, 126, 118, 48, 185,
                  248, 65, 34, 85, 12, 87, 197, 69, 121, 0, 21, 5, 152, 20, 7, 197>>,
              amount: 100_000_000,
              type: :UCO,
              timestamp: ~U[2021-05-05 13:11:19.000Z]
            }
            |> VersionedUnspentOutput.wrap_unspent_output(current_protocol_version())
          ]
        },
        signature:
          <<67, 12, 4, 246, 155, 34, 32, 108, 195, 54, 139, 8, 77, 152, 5, 55, 233, 217, 126, 181,
            204, 195, 215, 239, 124, 186, 99, 187, 251, 243, 201, 6, 122, 65, 238, 221, 14, 89,
            120, 225, 39, 33, 95, 95, 225, 113, 143, 200, 47, 96, 239, 66, 182, 168, 35, 129, 240,
            35, 183, 47, 69, 154, 37, 172>>,
        protocol_version: current_protocol_version()
      }

      assert stamp ==
               stamp
               |> ValidationStamp.serialize()
               |> ValidationStamp.deserialize()
               |> elem(0)
    end
  end
end
