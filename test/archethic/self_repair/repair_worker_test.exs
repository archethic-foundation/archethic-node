defmodule Archethic.SelfRepair.RepairWorkerTest do
  @moduledoc false
  use ArchethicCase, async: false

  alias Archethic.SelfRepair
  alias Archethic.SelfRepair.RepairWorker
  alias Archethic.SelfRepair.RepairRegistry

  import ArchethicCase
  import Mock

  test "should start the worker if not already started" do
    genesis = random_address()

    assert [] == Registry.lookup(RepairRegistry, genesis)

    with_mock(SelfRepair, replicate_transaction: fn _, _ -> :ok end) do
      :ok = RepairWorker.repair_addresses(genesis, random_address(), [random_address()])

      assert [{pid, _}] = Registry.lookup(RepairRegistry, genesis)

      await_process_end(pid)

      assert_called_exactly(SelfRepair.replicate_transaction(:_, :_), 2)
    end

    assert [] == Registry.lookup(RepairRegistry, genesis)
  end

  test "should replicate the transactions coming from sequential calls" do
    genesis = random_address()

    assert [] == Registry.lookup(RepairRegistry, genesis)

    with_mock(SelfRepair, replicate_transaction: fn _, _ -> :ok end) do
      :ok =
        RepairWorker.repair_addresses(genesis, random_address(), [
          random_address(),
          random_address()
        ])

      :ok = RepairWorker.repair_addresses(genesis, random_address(), [])
      :ok = RepairWorker.repair_addresses(genesis, random_address(), [random_address()])

      assert [{pid, _}] = Registry.lookup(RepairRegistry, genesis)

      await_process_end(pid)

      assert_called_exactly(SelfRepair.replicate_transaction(:_, :_), 6)
    end

    assert [] == Registry.lookup(RepairRegistry, genesis)
  end

  test "should not replicate the transactions that were already replicated" do
    genesis = random_address()

    assert [] == Registry.lookup(RepairRegistry, genesis)

    with_mock(SelfRepair, replicate_transaction: fn _, _ -> :ok end) do
      address2 = random_address()
      address3 = random_address()
      address_io1 = random_address()
      address_io2 = random_address()
      address_io3 = random_address()

      :ok = RepairWorker.repair_addresses(genesis, address2, [address_io1, address_io2])
      :ok = RepairWorker.repair_addresses(genesis, address3, [address_io2, address_io3])
      :ok = RepairWorker.repair_addresses(genesis, address3, [])

      assert [{pid, _}] = Registry.lookup(RepairRegistry, genesis)

      await_process_end(pid)

      assert_called_exactly(SelfRepair.replicate_transaction(:_, :_), 5)
    end

    assert [] == Registry.lookup(RepairRegistry, genesis)
  end

  defp await_process_end(pid) do
    ref = Process.monitor(pid)

    receive do
      :DOWN -> :ok
      {:DOWN, ^ref, _, _, _} -> :ok
    end
  end
end
