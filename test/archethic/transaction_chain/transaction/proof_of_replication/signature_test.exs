defmodule Archethic.TransactionChain.Transaction.ProofOfReplication.SignatureTest do
  use ArchethicCase
  import ArchethicCase

  alias Archethic.Crypto
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ProofOfReplication.Signature
  alias Archethic.TransactionChain.TransactionSummary

  alias Archethic.TransactionFactory

  test "create/1 should create a proof signature" do
    tx = TransactionFactory.create_valid_transaction()
    genesis = Transaction.previous_address(tx)
    tx_summary = TransactionSummary.from_transaction(tx, genesis)

    expected_public_key = Crypto.first_node_public_key()
    expected_mining_key = Crypto.mining_node_public_key()

    assert %Signature{
             node_public_key: ^expected_public_key,
             node_mining_key: ^expected_mining_key,
             signature: signature
           } = Signature.create(tx_summary)

    raw_data = TransactionSummary.serialize(tx_summary)

    assert Crypto.verify?(signature, raw_data, expected_mining_key)
  end

  describe "valid?/2" do
    test "should return true of the signature is valid" do
      tx = TransactionFactory.create_valid_transaction()
      genesis = Transaction.previous_address(tx)
      tx_summary = TransactionSummary.from_transaction(tx, genesis)

      proof_signature = Signature.create(tx_summary)

      assert Signature.valid?(proof_signature, tx_summary)
    end

    test "should return false if the signature public key is invalid" do
      tx = TransactionFactory.create_valid_transaction()
      genesis = Transaction.previous_address(tx)
      tx_summary = TransactionSummary.from_transaction(tx, genesis)

      proof_signature = %Signature{
        Signature.create(tx_summary)
        | node_mining_key: random_public_key(:bls)
      }

      refute Signature.valid?(proof_signature, tx_summary)
    end

    test "should return false if the signature is invalid" do
      tx1 = TransactionFactory.create_valid_transaction()
      genesis = Transaction.previous_address(tx1)
      tx_summary1 = TransactionSummary.from_transaction(tx1, genesis)

      proof_signature = Signature.create(tx_summary1)
      assert Signature.valid?(proof_signature, tx_summary1)

      tx2 = TransactionFactory.create_valid_transaction([], content: "Hello")
      genesis = Transaction.previous_address(tx2)
      tx_summary2 = TransactionSummary.from_transaction(tx2, genesis)

      refute Signature.valid?(proof_signature, tx_summary2)
    end
  end

  test "serialization" do
    tx = TransactionFactory.create_valid_transaction()
    genesis = Transaction.previous_address(tx)
    tx_summary = TransactionSummary.from_transaction(tx, genesis)

    proof_signature = Signature.create(tx_summary)

    assert {proof_signature, <<>>} ==
             proof_signature |> Signature.serialize() |> Signature.deserialize()
  end
end
