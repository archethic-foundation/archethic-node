defmodule Uniris.TransactionChain.Transaction.CrossValidationStampTest do
  use UnirisCase
  use ExUnitProperties

  import Mox

  alias Uniris.Crypto
  alias Uniris.TransactionChain.Transaction.CrossValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  doctest CrossValidationStamp

  property "symmetric sign/verify cross validation stamp" do
    check all(
            keypair_seed <- StreamData.binary(length: 32),
            inconsistencies <- gen_inconsistencies(),
            pow <- StreamData.binary(length: 33),
            poi <- StreamData.binary(length: 33),
            poe <- StreamData.binary(length: 64),
            signature <- StreamData.binary(length: 64)
          ) do
      {pub, pv} = Crypto.generate_deterministic_keypair(keypair_seed, :secp256r1)

      MockCrypto
      |> expect(:sign_with_node_key, &Crypto.sign(&1, pv))
      |> expect(:node_public_key, fn -> pub end)

      validation_stamp = %ValidationStamp{
        proof_of_work: pow,
        proof_of_integrity: poi,
        proof_of_election: poe,
        ledger_operations: %LedgerOperations{},
        signature: signature
      }

      cross_stamp =
        %CrossValidationStamp{node_public_key: node_public_key} =
        %CrossValidationStamp{inconsistencies: inconsistencies}
        |> CrossValidationStamp.sign(validation_stamp)

      assert node_public_key == pub
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
      :unspent_outputs,
      :node_movements
    ]
    |> StreamData.one_of()
    |> StreamData.uniq_list_of(max_length: 4, max_tries: 100)
  end
end
