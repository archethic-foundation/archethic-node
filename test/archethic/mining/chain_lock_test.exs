defmodule Archethic.Mining.ChainLockTest do
  @moduledoc false

  alias Archethic.Crypto
  alias Archethic.Mining.ChainLock
  alias Archethic.PubSub

  use ArchethicCase
  import ArchethicCase

  describe "lock" do
    test "should allow same address and hash to be locked multiple times" do
      address = random_address()
      hash = Crypto.hash(address)

      assert :ok == ChainLock.lock(address, hash)
      assert :ok == ChainLock.lock(address, hash)
      assert :ok == ChainLock.lock(address, hash)
    end

    test "should refuse same address to be locked with different hash" do
      address = random_address()
      hash1 = Crypto.hash(address)
      hash2 = Crypto.hash(hash1)

      assert :ok == ChainLock.lock(address, hash1)
      assert {:error, :already_locked} == ChainLock.lock(address, hash2)
    end

    test "should subscribe to PubSub new transaction" do
      address = random_address()
      hash = Crypto.hash(address)

      pid = GenServer.whereis({:via, PartitionSupervisor, {ChainLockSupervisor, address}})

      assert [] == Registry.keys(Archethic.PubSubRegistry, pid)

      ChainLock.lock(address, hash)

      assert [{:new_transaction, address}] == Registry.keys(Archethic.PubSubRegistry, pid)
    end
  end

  describe "unlock" do
    test "should return ok if there is no lock" do
      assert :ok == random_address() |> ChainLock.unlock()
    end

    test "should unlock address" do
      address = random_address()
      hash1 = Crypto.hash(address)
      hash2 = Crypto.hash(hash1)

      assert :ok == ChainLock.lock(address, hash1)
      assert {:error, :already_locked} == ChainLock.lock(address, hash2)
      assert :ok == ChainLock.unlock(address)
      assert :ok == ChainLock.lock(address, hash2)
    end

    test "should remove lock when transaction is replicated" do
      address = random_address()
      hash1 = Crypto.hash(address)
      hash2 = Crypto.hash(hash1)

      assert :ok == ChainLock.lock(address, hash1)
      assert {:error, :already_locked} == ChainLock.lock(address, hash2)
      PubSub.notify_new_transaction(address)
      assert :ok == ChainLock.lock(address, hash2)

      assert {:error, :already_locked} == ChainLock.lock(address, hash1)
      PubSub.notify_new_transaction(address, :transfer, DateTime.utc_now())
      assert :ok == ChainLock.lock(address, hash1)
    end

    test "should remove lock after mining timeout" do
      pid = start_supervised!({ChainLock, mining_timeout: 200})

      address = random_address()
      hash1 = Crypto.hash(address)
      hash2 = Crypto.hash(hash1)

      assert :ok == GenServer.call(pid, {:lock, address, hash1})
      assert {:error, :already_locked} == GenServer.call(pid, {:lock, address, hash2})
      Process.sleep(205)
      assert :ok == GenServer.call(pid, {:lock, address, hash2})
    end
  end
end
