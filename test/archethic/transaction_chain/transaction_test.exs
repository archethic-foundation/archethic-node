defmodule ArchEthic.TransactionChain.TransactionTest do
  use ArchEthicCase, async: false

  alias ArchEthic.Crypto

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.CrossValidationStamp
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ledger
  alias ArchEthic.TransactionChain.TransactionData.NFTLedger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger

  doctest ArchEthic.TransactionChain.Transaction

  describe "new/2" do
    test "with type ':node' create a new transaction using the node keys" do
      tx = Transaction.new(:node, %TransactionData{})

      assert tx.address == Crypto.hash(Crypto.next_node_public_key())
      assert tx.previous_public_key == Crypto.last_node_public_key()

      assert Crypto.verify?(
               tx.origin_signature,
               tx |> Transaction.extract_for_origin_signature() |> Transaction.serialize(),
               Crypto.first_node_public_key()
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

      assert Crypto.verify?(
               tx.origin_signature,
               tx |> Transaction.extract_for_origin_signature() |> Transaction.serialize(),
               Crypto.first_node_public_key()
             )
    end
  end

  test "new/4 should create transaction with specific seed and index" do
    tx = Transaction.new(:node, %TransactionData{}, "seed", 0)
    tx2 = Transaction.new(:node, %TransactionData{}, "seed", 1)

    assert Crypto.hash(tx2.previous_public_key) == tx.address
  end
end
