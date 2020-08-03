defmodule Uniris.Transaction.CrossValidationStampTest do
  use UnirisCase

  import Mox

  alias Uniris.Crypto
  alias Uniris.Transaction.CrossValidationStamp
  alias Uniris.Transaction.ValidationStamp
  alias Uniris.Transaction.ValidationStamp.LedgerOperations

  doctest CrossValidationStamp

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
          :signature,
          :proof_of_work,
          :proof_of_integrity,
          :ledger_operations
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
            :signature,
            :proof_of_work,
            :proof_of_integrity,
            :ledger_operations
          ]
        )

      assert node_public_key == pub

      assert Crypto.verify(
               sig,
               [
                 0,
                 1,
                 2,
                 3
               ]
               |> :erlang.list_to_binary(),
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
               }
               |> ValidationStamp.serialize(),
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
               :proof_of_work,
               :proof_of_integrity,
               :ledger_operations,
               :signature
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
