defmodule UnirisCore.Transaction.CrossValidationStampTest do
  use UnirisCoreCase

  import Mox

  alias UnirisCore.Crypto
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations
  alias UnirisCore.Transaction.CrossValidationStamp

  describe "new/2" do
    test "should create cross validated signing the inconsistencies" do
      {pub, pv} = Crypto.generate_deterministic_keypair("seed", :secp256r1)

      MockCrypto
      |> expect(:sign_with_node_key, fn stamp ->
        Crypto.sign(stamp, pv)
      end)
      |> expect(:node_public_key, fn -> pub end)

      %CrossValidationStamp{
        signature: sig,
        inconsistencies: [
          :invalid_proof_of_work,
          :invalid_proof_of_integrity,
          :invalid_ledger_operations,
          :invalid_signature
        ],
        node_public_key: node_public_key
      } =
        CrossValidationStamp.new(
          %ValidationStamp{
            proof_of_work: "",
            proof_of_integrity: "",
            ledger_operations: %LedgerOperations{},
            signature: ""
          },
          [
            :invalid_proof_of_work,
            :invalid_proof_of_integrity,
            :invalid_ledger_operations,
            :invalid_signature
          ]
        )

      assert node_public_key == pub

      assert Crypto.verify(
               sig,
               [
                 :invalid_proof_of_work,
                 :invalid_proof_of_integrity,
                 :invalid_ledger_operations,
                 :invalid_signature
               ],
               pub
             )
    end

    test "should create cross validated signing the validation stamp" do
      {pub, pv} = Crypto.generate_deterministic_keypair("seed", :secp256r1)

      MockCrypto
      |> expect(:sign_with_node_key, fn stamp ->
        Crypto.sign(stamp, pv)
      end)
      |> expect(:node_public_key, fn -> pub end)

      %CrossValidationStamp{
        signature: sig,
        inconsistencies: [],
        node_public_key: node_public_key
      } =
        CrossValidationStamp.new(
          %ValidationStamp{
            proof_of_work: "",
            proof_of_integrity: "",
            ledger_operations: %LedgerOperations{},
            signature: ""
          },
          []
        )

      assert node_public_key == pub

      assert Crypto.verify(
               sig,
               %ValidationStamp{
                 proof_of_work: "",
                 proof_of_integrity: "",
                 ledger_operations: %LedgerOperations{},
                 signature: ""
               },
               pub
             )
    end
  end

  describe "valid?/2" do
    test "should validate signature using inconsistencies" do
      {pub, pv} = Crypto.generate_deterministic_keypair("seed", :secp256r1)

      MockCrypto
      |> expect(:sign_with_node_key, fn stamp ->
        Crypto.sign(stamp, pv)
      end)
      |> expect(:node_public_key, fn -> pub end)

      stamp = %ValidationStamp{
        proof_of_work: "",
        proof_of_integrity: "",
        ledger_operations: %LedgerOperations{},
        signature: ""
      }

      assert stamp
             |> CrossValidationStamp.new([
               :invalid_proof_of_work,
               :invalid_proof_of_integrity,
               :invalid_ledger_operations,
               :invalid_signature
             ])
             |> CrossValidationStamp.valid?(stamp)
    end

    test "should validate signature using validation stamp" do
      {pub, pv} = Crypto.generate_deterministic_keypair("seed", :secp256r1)

      MockCrypto
      |> expect(:sign_with_node_key, fn stamp ->
        Crypto.sign(stamp, pv)
      end)
      |> expect(:node_public_key, fn -> pub end)

      stamp = %ValidationStamp{
        proof_of_work: "",
        proof_of_integrity: "",
        ledger_operations: %LedgerOperations{},
        signature: ""
      }

      assert stamp
             |> CrossValidationStamp.new([])
             |> CrossValidationStamp.valid?(stamp)
    end
  end
end
