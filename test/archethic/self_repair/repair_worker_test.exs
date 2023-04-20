defmodule Archethic.SelfRepair.RepairWorkerTest do
  @moduledoc false
  use ArchethicCase, async: false

  alias Archethic.SelfRepair
  alias Archethic.SelfRepair.RepairWorker

  import Mock

  test "should start the worker if not already started" do
    assert 0 = Registry.count(Archethic.SelfRepair.RepairRegistry)

    with_mock(SelfRepair, replicate_transaction: fn _, _ -> :ok end) do
      :ok = RepairWorker.repair_addresses("Alice1", "Alice2", ["Bob1"])
      assert 1 = Registry.count(Archethic.SelfRepair.RepairRegistry)

      Process.sleep(100)
      assert_called_exactly(SelfRepair.replicate_transaction(:_, :_), 2)
    end

    assert 0 = Registry.count(Archethic.SelfRepair.RepairRegistry)
  end

  test "should replicate the transactions coming from initial call" do
    assert 0 = Registry.count(Archethic.SelfRepair.RepairRegistry)

    with_mock(SelfRepair, replicate_transaction: fn _, _ -> :ok end) do
      :ok = RepairWorker.repair_addresses("Alice1", "Alice2", ["Bob1", "Bob2"])
      assert 1 = Registry.count(Archethic.SelfRepair.RepairRegistry)

      Process.sleep(100)
      assert_called_exactly(SelfRepair.replicate_transaction(:_, :_), 3)
    end

    assert 0 = Registry.count(Archethic.SelfRepair.RepairRegistry)
  end

  test "should replicate the transactions coming from sequential calls" do
    assert 0 = Registry.count(Archethic.SelfRepair.RepairRegistry)

    with_mock(SelfRepair, replicate_transaction: fn _, _ -> :ok end) do
      :ok = RepairWorker.repair_addresses("Alice1", "Alice2", ["Bob1", "Bob2"])
      :ok = RepairWorker.repair_addresses("Alice1", "Alice3", [])
      :ok = RepairWorker.repair_addresses("Alice1", "Alice4", ["Bob3"])
      assert 1 = Registry.count(Archethic.SelfRepair.RepairRegistry)

      Process.sleep(100)
      assert_called_exactly(SelfRepair.replicate_transaction(:_, :_), 6)
    end

    assert 0 = Registry.count(Archethic.SelfRepair.RepairRegistry)
  end
end
