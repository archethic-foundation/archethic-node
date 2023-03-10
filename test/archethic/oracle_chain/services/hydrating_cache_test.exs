defmodule ArchethicCache.OracleChain.Services.HydratingCacheTest do
  alias Archethic.OracleChain.Services.HydratingCache

  use ExUnit.Case

  test "should receive the same value until next refresh" do
    {:ok, pid} =
      HydratingCache.start_link(
        mfa: {DateTime, :utc_now, []},
        refresh_interval: 100,
        ttl: :infinity
      )

    # 1ms required just so it has the time to receive the :hydrate msg
    Process.sleep(1)
    {:ok, date} = HydratingCache.get(pid)

    Process.sleep(10)
    assert {:ok, ^date} = HydratingCache.get(pid)

    Process.sleep(10)
    assert {:ok, ^date} = HydratingCache.get(pid)

    Process.sleep(10)
    assert {:ok, ^date} = HydratingCache.get(pid)

    Process.sleep(10)
    assert {:ok, ^date} = HydratingCache.get(pid)

    Process.sleep(100)
    {:ok, date2} = HydratingCache.get(pid)
    assert date != date2
  end

  test "should discard the value after the ttl is reached" do
    {:ok, pid} =
      HydratingCache.start_link(
        mfa: {DateTime, :utc_now, []},
        refresh_interval: 100,
        ttl: 50
      )

    # 1ms required just so it has the time to receive the :hydrate msg
    Process.sleep(1)
    {:ok, _date} = HydratingCache.get(pid)

    Process.sleep(50)
    assert :error = HydratingCache.get(pid)
  end

  test "should refresh the value after a discard" do
    {:ok, pid} =
      HydratingCache.start_link(
        mfa: {DateTime, :utc_now, []},
        refresh_interval: 100,
        ttl: 50
      )

    # 1ms required just so it has the time to receive the :hydrate msg
    Process.sleep(1)
    {:ok, date} = HydratingCache.get(pid)

    Process.sleep(50)
    assert :error = HydratingCache.get(pid)

    Process.sleep(50)
    {:ok, date2} = HydratingCache.get(pid)

    assert date != date2
  end

  test "should not crash if the module is undefined" do
    {:ok, pid} =
      HydratingCache.start_link(
        mfa: {NonExisting, :function, []},
        refresh_interval: 100,
        ttl: 50
      )

    # 1ms required just so it has the time to receive the :hydrate msg
    Process.sleep(1)
    assert :error = HydratingCache.get(pid)

    Process.sleep(50)
    assert :error = HydratingCache.get(pid)

    Process.sleep(100)
    assert :error = HydratingCache.get(pid)
  end

  test "should await the timeout to clean the value" do
    {:ok, pid} =
      HydratingCache.start_link(
        mfa: {Process, :sleep, [100]},
        refresh_interval: 100,
        ttl: :infinity
      )

    # 1ms required just so it has the time to receive the :hydrate msg
    Process.sleep(1)

    assert :error = HydratingCache.get(pid, 1)
  end
end
