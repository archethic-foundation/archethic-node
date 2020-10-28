defmodule Uniris.TransactionChain.TransactionTest do
  use UnirisCase, async: false

  alias Uniris.Crypto

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.CrossValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Uniris.TransactionChain.TransactionData

  doctest Uniris.TransactionChain.Transaction

  describe "new/2" do
    test "with type ':node' create a new transaction using the node keys" do
      tx = Transaction.new(:node, %TransactionData{})

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
end
