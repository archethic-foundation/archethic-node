defmodule UnirisCore.TransactionTest do
  use UnirisCoreCase, async: false

  alias UnirisCore.Crypto

  alias UnirisCore.Transaction
  alias UnirisCore.Transaction.CrossValidationStamp

  alias UnirisCore.TransactionData

  doctest UnirisCore.Transaction

  describe "new/2" do
    test "with type ':node' create a new transaction using the node keys" do
      tx = Transaction.new(:node, %TransactionData{})
      assert Transaction.valid_pending_transaction?(tx)

      assert tx.address == Crypto.hash(Crypto.node_public_key(Crypto.number_of_node_keys() + 1))
      assert tx.previous_public_key == Crypto.node_public_key(Crypto.number_of_node_keys())

      assert Crypto.verify(
               tx.origin_signature,
               tx |> Transaction.extract_for_origin_signature() |> Transaction.serialize(),
               Crypto.node_public_key(0)
             )
    end

    test "with type ':node_shared_secrets' create a new transaction using the node shared secrets keys" do
      tx = Transaction.new(:node_shared_secrets, %TransactionData{})
      assert Transaction.valid_pending_transaction?(tx)

      assert tx.address ==
               Crypto.hash(
                 Crypto.node_shared_secrets_public_key(
                   Crypto.number_of_node_shared_secrets_keys() + 1
                 )
               )

      key_index = Crypto.number_of_node_shared_secrets_keys()
      assert tx.previous_public_key == Crypto.node_shared_secrets_public_key(key_index)

      assert Crypto.verify(
               tx.origin_signature,
               tx |> Transaction.extract_for_origin_signature() |> Transaction.serialize(),
               Crypto.node_public_key(0)
             )
    end
  end

  test "new/4 should create transaction with specific seed and index" do
    tx = Transaction.new(:node, %TransactionData{}, "seed", 0)
    tx2 = Transaction.new(:node, %TransactionData{}, "seed", 1)

    assert Crypto.hash(tx2.previous_public_key) == tx.address
  end

  describe "atomic_commitment?/1" do
    test "should return true when all the cross validation stamps inconsistencies are identical" do
      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      assert %{
               tx
               | cross_validation_stamps: [
                   %CrossValidationStamp{inconsistencies: []},
                   %CrossValidationStamp{inconsistencies: []},
                   %CrossValidationStamp{inconsistencies: []}
                 ]
             }
             |> Transaction.atomic_commitment?()
    end

    test "should return false when event one of the cross validation stamps inconsistencies is not identical" do
      tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

      assert false ==
               %{
                 tx
                 | cross_validation_stamps: [
                     %CrossValidationStamp{inconsistencies: [:invalid_signature]},
                     %CrossValidationStamp{inconsistencies: []},
                     %CrossValidationStamp{inconsistencies: []}
                   ]
               }
               |> Transaction.atomic_commitment?()

      assert false ==
               %{
                 tx
                 | cross_validation_stamps: [
                     %CrossValidationStamp{inconsistencies: []},
                     %CrossValidationStamp{inconsistencies: [:invalid_proof_of_work]},
                     %CrossValidationStamp{inconsistencies: [:invalid_proof_of_work]}
                   ]
               }
               |> Transaction.atomic_commitment?()

      assert false ==
               %{
                 tx
                 | cross_validation_stamps: [
                     %CrossValidationStamp{inconsistencies: [:invalid_signature]},
                     %CrossValidationStamp{inconsistencies: [:invalid_proof_of_work]},
                     %CrossValidationStamp{inconsistencies: [:invalid_proof_of_integrity]}
                   ]
               }
               |> Transaction.atomic_commitment?()
    end
  end
end
