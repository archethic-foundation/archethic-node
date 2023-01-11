defmodule Archethic.ReplicationTransactionPoolTest do
  use ExUnit.Case

  alias Archethic.TransactionChain.Transaction
  alias Archethic.Replication.TransactionPool

  test "add_transaction/2 should add transaction in the pool" do
    {:ok, pid} = TransactionPool.start_link([clean_interval: 0], [])
    address = :crypto.strong_rand_bytes(33)
    now = DateTime.utc_now()
    TransactionPool.add_transaction(pid, %Transaction{address: address, type: :transfer})

    assert %{transactions: %{^address => {_, expire_at}}} = :sys.get_state(pid)
    assert DateTime.diff(expire_at, now, :second) == 60
  end

  test "pop_transaction/2 should get and remove a registed transaction in the pool" do
    {:ok, pid} = TransactionPool.start_link([clean_interval: 0], [])
    address = :crypto.strong_rand_bytes(33)
    tx = %Transaction{address: address, type: :transfer}
    TransactionPool.add_transaction(pid, tx)
    {:ok, ^tx} = TransactionPool.pop_transaction(pid, address)
    assert %{transactions: %{}} = :sys.get_state(pid)
  end

  test "should clean too long transactions" do
    {:ok, pid} = TransactionPool.start_link([clean_interval: 1000, ttl: 500], [])
    address = :crypto.strong_rand_bytes(33)
    TransactionPool.add_transaction(pid, %Transaction{address: address, type: :transfer})

    Process.sleep(1200)
    assert %{transactions: %{}} = :sys.get_state(pid)
  end
end
