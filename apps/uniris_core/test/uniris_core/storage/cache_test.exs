defmodule UnirisCore.Storage.CacheTest do
  use UnirisCoreCase

  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.TransactionData.Ledger
  alias UnirisCore.TransactionData.UCOLedger
  alias UnirisCore.TransactionData.Ledger.Transfer
  alias UnirisCore.Storage.Cache

  setup do
    start_supervised!(Cache)
    :ok
  end

  describe "store_transaction/1" do
    test "should insert the transaction" do
      tx = Transaction.new(:node_shared_secrets, %TransactionData{})
      :ok = Cache.store_transaction(tx)
      assert tx == Cache.get_transaction(tx.address)
    end

    test "should index the transaction as node transaction" do
      tx = Transaction.new(:node, %TransactionData{})
      :ok = Cache.store_transaction(tx)
      assert [tx] == Cache.node_transactions()
    end

    test "should index the transaction as node shared secrets transaction" do
      tx = Transaction.new(:node_shared_secrets, %TransactionData{})
      :ok = Cache.store_transaction(tx)
      assert tx == Cache.last_node_shared_secrets_transaction()

      tx2 = Transaction.new(:node_shared_secrets, %TransactionData{})
      :ok = Cache.store_transaction(tx2)
      assert tx2 == Cache.last_node_shared_secrets_transaction()
    end

    test "should index the transaction as unspent outputs" do
      tx =
        Transaction.new(
          :transfer,
          %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{transfers: [%Transfer{to: "fake_address", amount: 10}]}
            }
          },
          "seed",
          0
        )

      :ok = Cache.store_transaction(tx)
      assert [tx] == Cache.get_unspent_outputs("fake_address")
    end
  end

  test "store_ko_transaction/1 should insert the transaction in the ko table" do
    tx = Transaction.new(:node_shared_secrets, %TransactionData{})

    tx = %{
      tx
      | cross_validation_stamps: [{"signature", [:invalid_proof_of_work], "node_public_key"}]
    }

    :ok = Cache.store_ko_transaction(tx)
    assert true == Cache.ko_transaction?(tx.address)
  end

  test "last_transaction_address/1 should retrieve the last transaction on a chain" do
    tx1 = Transaction.new(:transfer, %TransactionData{}, "seed", 0)
    tx2 = Transaction.new(:transfer, %TransactionData{}, "seed", 1)
    tx3 = Transaction.new(:transfer, %TransactionData{}, "seed", 2)

    Cache.store_transaction(tx1)
    Cache.store_transaction(tx2)
    Cache.store_transaction(tx3)

    assert {:ok, tx3.address} == Cache.last_transaction_address(tx1.address)
    assert {:ok, tx3.address} == Cache.last_transaction_address(tx2.address)
    assert {:ok, tx3.address} == Cache.last_transaction_address(tx3.address)
  end

  test "list_transactions/1 should return a stream of transaction" do
    Enum.each(1..50, fn i ->
      Cache.store_transaction(Transaction.new(:transfer, %TransactionData{}, "seed", i))
    end)

    assert 50 == Enum.count(Cache.list_transactions(0))
    assert 20 == Enum.count(Cache.list_transactions(20))
  end

end
