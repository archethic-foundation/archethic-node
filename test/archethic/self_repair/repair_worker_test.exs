defmodule Archethic.SelfRepair.RepairWorkerTest do
  @moduledoc false
  use ArchethicCase, async: false

  alias Archethic.SelfRepair
  alias Archethic.SelfRepair.RepairWorker

  import Mock

  test "should start the worker if not already started" do
    assert 0 = Registry.count(Archethic.SelfRepair.RepairRegistry)

    with_mock(SelfRepair, replicate_transaction: fn _, _, _ -> :ok end) do
      :ok = RepairWorker.repair_addresses("Alice1", "Alice2", ["Bob1"])
      assert 1 = Registry.count(Archethic.SelfRepair.RepairRegistry)

      Process.sleep(100)
      assert_called_exactly(SelfRepair.replicate_transaction(:_, :_, :_), 2)
    end

    assert 0 = Registry.count(Archethic.SelfRepair.RepairRegistry)
  end

  test "should replicate the transactions coming from sequential calls" do
    assert 0 = Registry.count(Archethic.SelfRepair.RepairRegistry)

    with_mock(SelfRepair,
      replicate_transaction: fn _, _, _ ->
        Process.sleep(10)
        :ok
      end
    ) do
      :ok = RepairWorker.repair_addresses("Alice1", "Alice2", ["Bob1", "Bob2"])
      :ok = RepairWorker.repair_addresses("Alice1", "Alice3", [])
      :ok = RepairWorker.repair_addresses("Alice1", "Alice4", ["Bob3"])

      assert 1 = Registry.count(Archethic.SelfRepair.RepairRegistry)

      Process.sleep(100)
      assert_called_exactly(SelfRepair.replicate_transaction(:_, :_, :_), 6)
    end

    assert 0 = Registry.count(Archethic.SelfRepair.RepairRegistry)
  end

  test "should not replicate the transactions that were already replicated" do
    assert 0 = Registry.count(Archethic.SelfRepair.RepairRegistry)

    with_mock(SelfRepair,
      replicate_transaction: fn _, _, _ ->
        Process.sleep(10)
        :ok
      end
    ) do
      :ok = RepairWorker.repair_addresses("Alice1", "Alice2", ["Bob1", "Bob2"])
      :ok = RepairWorker.repair_addresses("Alice1", "Alice3", ["Bob2", "Bob3"])
      :ok = RepairWorker.repair_addresses("Alice1", "Alice3", [])
      assert 1 = Registry.count(Archethic.SelfRepair.RepairRegistry)

      Process.sleep(100)
      assert_called_exactly(SelfRepair.replicate_transaction(:_, :_, :_), 5)
    end

    assert 0 = Registry.count(Archethic.SelfRepair.RepairRegistry)
  end
end
