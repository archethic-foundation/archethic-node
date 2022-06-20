defmodule Archethic.TransactionChain.TransactionTest do
  @moduledoc false
  use ArchethicCase, async: false

  alias Archethic.Crypto

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
  # alias Archethic.TransactionChain.Transaction.ValidationStamp
  # alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.NFTLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger

  doctest Archethic.TransactionChain.Transaction

  describe "new/2" do
    test "with type ':node' create a new transaction using the node keys" do
      tx = Transaction.new(:node, %TransactionData{})

      assert tx.address == Crypto.derive_address(Crypto.next_node_public_key())
      assert tx.previous_public_key == Crypto.last_node_public_key()

      assert Crypto.verify?(
               tx.origin_signature,
               tx |> Transaction.extract_for_origin_signature() |> Transaction.serialize(),
               Crypto.origin_node_public_key()
             )
    end

    test "with type ':node_shared_secrets' create a new transaction using the node shared secrets keys" do
      tx = Transaction.new(:node_shared_secrets, %TransactionData{})

      assert tx.address ==
               Crypto.derive_address(
                 Crypto.node_shared_secrets_public_key(
                   Crypto.number_of_node_shared_secrets_keys() + 1
                 )
               )

      key_index = Crypto.number_of_node_shared_secrets_keys()
      assert tx.previous_public_key == Crypto.node_shared_secrets_public_key(key_index)

      assert Crypto.verify?(
               tx.origin_signature,
               tx |> Transaction.extract_for_origin_signature() |> Transaction.serialize(),
               Crypto.origin_node_public_key()
             )
    end
  end

  test "new/4 should create transaction with specific seed and index" do
    tx = Transaction.new(:node, %TransactionData{}, "seed", 0)
    tx2 = Transaction.new(:node, %TransactionData{}, "seed", 1)

    assert Crypto.derive_address(tx2.previous_public_key) == tx.address
  end
end
