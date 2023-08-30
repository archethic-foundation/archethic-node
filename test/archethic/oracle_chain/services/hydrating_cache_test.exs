defmodule ArchethicCache.OracleChain.Services.HydratingCacheTest do
  alias Archethic.OracleChain.Services.HydratingCache

  use ExUnit.Case
  @moduletag capture_log: true

  test "should receive the same value until next refresh" do
    {:ok, pid} =
      HydratingCache.start_link(
        mfa: {DateTime, :utc_now, []},
        refresh_interval: 100,
        ttl: :infinity
      )

    :erlang.trace(pid, true, [:receive])
    assert_receive {:trace, ^pid, :receive, :hydrate}
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

    assert_receive {:trace, ^pid, :receive, {:DOWN, _, _, _, _}}
    assert_receive {:trace, ^pid, :receive, :hydrate}
    Process.sleep(1)
    {:ok, date2} = HydratingCache.get(pid)
    assert date != date2
  end

  test "should work with cron interval" do
    {:ok, pid} =
      HydratingCache.start_link(
        mfa: {DateTime, :utc_now, []},
        refresh_interval: "* * * * *",
        ttl: :infinity
      )

    :erlang.trace(pid, true, [:receive])
    assert_receive {:trace, ^pid, :receive, :hydrate}
    Process.sleep(1)
    {:ok, date} = HydratingCache.get(pid)

    # minimum interval is 1s
    Process.sleep(1005)
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

    :erlang.trace(pid, true, [:receive])
    assert_receive {:trace, ^pid, :receive, :hydrate}
    Process.sleep(1)

    assert {:ok, _date} = HydratingCache.get(pid)

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

    :erlang.trace(pid, true, [:receive])
    assert_receive {:trace, ^pid, :receive, :hydrate}
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

    :erlang.trace(pid, true, [:receive])
    assert_receive {:trace, ^pid, :receive, :hydrate}
    assert_receive {:trace, ^pid, :receive, {_ref, {:error, %UndefinedFunctionError{}}}}
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

    :erlang.trace(pid, true, [:receive])
    assert_receive {:trace, ^pid, :receive, :hydrate}
    Process.sleep(1)

    assert :error = HydratingCache.get(pid, 1)
  end

  test "should kill the task if hydrating function takes longer than timeout" do
    {:ok, pid} =
      HydratingCache.start_link(
        mfa: {Process, :sleep, [200]},
        refresh_interval: 200,
        hydrating_function_timeout: 100,
        ttl: :infinity
      )

    :erlang.trace(pid, true, [:receive])

    state_begin = :sys.get_state(pid)

    Process.sleep(100)

    assert_receive {:trace, ^pid, :receive, :hydrate}
    assert_receive {:trace, ^pid, :receive, {:kill_hydrating_task, _}}

    # check task has been killed but not genserver
    refute Process.alive?(:sys.get_state(pid).hydrating_task.pid)
    assert Process.alive?(pid)

    # genserver still able to reply
    assert :error = HydratingCache.get(pid)

    Process.sleep(200)

    # make sure a new timer has been started
    assert :sys.get_state(pid).hydrating_timer != state_begin.hydrating_timer
  end
end
