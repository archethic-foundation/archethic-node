defmodule Archethic.TransactionChain.TransactionTest do
  @moduledoc false
  use ArchethicCase, async: false

  import ArchethicCase, only: [current_transaction_version: 0, current_protocol_version: 0]

  alias Archethic.Crypto
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger

  alias Archethic.TransactionFactory

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

  describe "valid_stamps_signature?/2" do
    test "should return false if validation stamp signature is invalid" do
      tx = TransactionFactory.create_transaction_with_invalid_validation_stamp_signature()

      keys = [[Crypto.first_node_public_key()]]

      refute Transaction.valid_stamps_signature?(tx, keys)
    end

    test "should return true if validation stamp signature is good" do
      tx = TransactionFactory.create_valid_transaction()

      keys = [[Crypto.first_node_public_key()]]

      assert Transaction.valid_stamps_signature?(tx, keys)
    end

    test "should return true if validation stamp signature is good having a list of public keys" do
      tx = TransactionFactory.create_valid_transaction()

      keys = [
        [create_random_key(), Crypto.first_node_public_key()],
        [create_random_key(), create_random_key()]
      ]

      assert Transaction.valid_stamps_signature?(tx, keys)
    end

    test "should return false if multiple cross validation stamps are from the same node" do
      tx = TransactionFactory.create_valid_transaction()
      cross_stamps = tx.cross_validation_stamps

      tx = %Transaction{tx | cross_validation_stamps: cross_stamps ++ cross_stamps}

      keys = [[Crypto.first_node_public_key()]]

      refute Transaction.valid_stamps_signature?(tx, keys)
    end

    test "should return false if cross validation stamps are invalid" do
      tx = TransactionFactory.create_valid_transaction()

      cross_stamps =
        tx.cross_validation_stamps
        |> Enum.map(fn cross_stamp ->
          %{cross_stamp | signature: :crypto.strong_rand_bytes(32)}
        end)

      tx = %Transaction{tx | cross_validation_stamps: cross_stamps}

      keys = [[Crypto.first_node_public_key()]]

      refute Transaction.valid_stamps_signature?(tx, keys)
    end
  end

  defp create_random_key(), do: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
end
