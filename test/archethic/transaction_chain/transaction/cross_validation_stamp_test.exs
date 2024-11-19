defmodule Archethic.TransactionChain.Transaction.CrossValidationStampTest do
  use ArchethicCase
  use ExUnitProperties
  import ArchethicCase

  alias Archethic.Crypto
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  doctest CrossValidationStamp

  property "symmetric sign/verify cross validation stamp" do
    check all(
            inconsistencies <- gen_inconsistencies(),
            pow <- StreamData.binary(length: 32),
            poi <- StreamData.binary(length: 33),
            poe <- StreamData.binary(length: 64),
            signature <- StreamData.binary(length: 64),
            protocol_version <- StreamData.integer(1..Archethic.Mining.protocol_version())
          ) do
      pub = Crypto.mining_node_public_key()

      validation_stamp = %ValidationStamp{
        genesis_address: random_address(),
        timestamp: DateTime.utc_now(),
        proof_of_work: <<0::8, 0::8, pow::binary>>,
        proof_of_integrity: poi,
        proof_of_election: poe,
        ledger_operations: %LedgerOperations{},
        signature: signature,
        protocol_version: protocol_version
      }

      cross_stamp =
        %CrossValidationStamp{node_mining_key: node_mining_key} =
        %CrossValidationStamp{inconsistencies: inconsistencies}
        |> CrossValidationStamp.sign(validation_stamp)

      assert node_mining_key == pub
      assert CrossValidationStamp.valid_signature?(cross_stamp, validation_stamp)
    end
  end

  defp gen_inconsistencies do
    [
      :signature,
      :proof_of_work,
      :proof_of_integrity,
      :transaction_fee,
      :transaction_movements,
      :unspent_outputs
    ]
    |> StreamData.one_of()
    |> StreamData.uniq_list_of(max_length: 4, max_tries: 100)
  end
end
