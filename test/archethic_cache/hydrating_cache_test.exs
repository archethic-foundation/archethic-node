defmodule ArchethicCache.HydratingCacheTest do
  alias ArchethicCache.HydratingCache

  use ExUnit.Case

  test "If `key` is not associated with any function, return `{:error, :not_registered}`" do
    {:ok, pid} = HydratingCache.start_link(:test_service)
    assert HydratingCache.get(pid, "unexisting_key") == {:error, :not_registered}
  end

  test "If value stored, it is returned immediatly" do
    {:ok, pid} = HydratingCache.start_link(:test_service_normal)

    HydratingCache.register_function(
      pid,
      fn ->
        {:ok, 1}
      end,
      "simple_func",
      10_000,
      :infinity
    )

    assert {:ok, 1} = HydratingCache.get(pid, "simple_func")
  end

  test "Hydrating function runs periodically" do
    {:ok, pid} = HydratingCache.start_link(:test_service_periodic)

    :persistent_term.put("test", 1)

    HydratingCache.register_function(
      pid,
      fn ->
        value = :persistent_term.get("test")
        value = value + 1
        :persistent_term.put("test", value)
        {:ok, value}
      end,
      "test_inc",
      10,
      :infinity
    )

    Process.sleep(50)
    assert {:ok, value} = HydratingCache.get(pid, "test_inc")
    assert value >= 5
  end

  test "Update hydrating function while another one is running returns new hydrating value from new function" do
    {:ok, pid} = HydratingCache.start_link(:test_service_hydrating)

    HydratingCache.register_function(
      pid,
      fn ->
        Process.sleep(5000)
        {:ok, 1}
      end,
      "test_reregister",
      10_000,
      :infinity
    )

    HydratingCache.register_function(
      pid,
      fn ->
        {:ok, 2}
      end,
      "test_reregister",
      10_000,
      :infinity
    )

    Process.sleep(50)
    assert {:ok, 2} = HydratingCache.get(pid, "test_reregister")
  end

  test "Getting value while function is running and previous value is available returns value" do
    {:ok, pid} = HydratingCache.start_link(:test_service_running)

    HydratingCache.register_function(
      pid,
      fn ->
        {:ok, 1}
      end,
      "test_reregister",
      10_000,
      :infinity
    )

    HydratingCache.register_function(
      pid,
      fn ->
        Process.sleep(5000)
        {:ok, 2}
      end,
      "test_reregister",
      10_000,
      :infinity
    )

    assert {:ok, 1} = HydratingCache.get(pid, "test_reregister")
  end

  test "Two hydrating function can run at same time" do
    {:ok, pid} = HydratingCache.start_link(:test_service_simultaneous)

    HydratingCache.register_function(
      pid,
      fn ->
        Process.sleep(5000)
        {:ok, :result_timed}
      end,
      "timed_value",
      10_000,
      :infinity
    )

    HydratingCache.register_function(
      pid,
      fn ->
        {:ok, :result}
      end,
      "direct_value",
      10_000,
      :infinity
    )

    assert {:ok, :result} = HydratingCache.get(pid, "direct_value")
  end

  test "Querying key while first refreshed will block the calling process until timeout" do
    {:ok, pid} = HydratingCache.start_link(:test_service_block)

    HydratingCache.register_function(
      pid,
      fn ->
        Process.sleep(5000)
        {:ok, :valid_result}
      end,
      "delayed_result",
      10_000,
      :infinity
    )

    ## We query the value with timeout smaller than timed function
    assert {:error, :timeout} = HydratingCache.get(pid, "delayed_result", 1)
  end

  test "Multiple process can wait for a delayed value" do
    {:ok, pid} = HydratingCache.start_link(:test_service_delayed)

    HydratingCache.register_function(
      pid,
      fn ->
        Process.sleep(100)
        {:ok, :valid_result}
      end,
      "delayed_result",
      10_000,
      :infinity
    )

    results = Task.async_stream(1..10, fn _ -> HydratingCache.get(pid, "delayed_result") end)

    assert Enum.all?(results, fn
             {:ok, {:ok, :valid_result}} -> true
           end)
  end

  ## Resilience tests
  test "If hydrating function crash, key fsm will still be operationnal" do
    {:ok, pid} = HydratingCache.start_link(:test_service_crash)

    HydratingCache.register_function(
      pid,
      fn ->
        ## Exit hydrating function
        exit(1)
      end,
      :key,
      10_000,
      :infinity
    )

    Process.sleep(1)

    HydratingCache.register_function(
      pid,
      fn ->
        {:ok, :value}
      end,
      :key,
      10_000,
      :infinity
    )

    assert {:ok, :value} = HydratingCache.get(pid, :key)
  end

  ## This could occur if hydrating function takes time to answer.
  ## In this case, getting the value would return the old value, unless too
  ## much time occur where it would be discarded because of ttl
  test "value gets discarded after some time" do
    {:ok, pid} = HydratingCache.start_link(:test_service)

    HydratingCache.register_function(
      pid,
      fn ->
        case :persistent_term.get("flag", nil) do
          1 ->
            Process.sleep(5000)

          nil ->
            :persistent_term.put("flag", 1)
            {:ok, :value}
        end
      end,
      :key,
      10,
      20
    )

    assert {:ok, :value} = HydratingCache.get(pid, :key)
    Process.sleep(25)
    assert {:error, :discarded} = HydratingCache.get(pid, :key)
  end

  test "Can get a value while another request is waiting for results" do
    {:ok, pid} = HydratingCache.start_link(:test_service_wait)

    HydratingCache.register_function(
      pid,
      fn ->
        Process.sleep(5000)
        {:ok, :value}
      end,
      :key1,
      10_000,
      :infinity
    )

    :erlang.spawn(fn -> HydratingCache.get(pid, :key1, 15_000) end)

    HydratingCache.register_function(
      pid,
      fn ->
        {:ok, :value2}
      end,
      :key2,
      10_000,
      :infinity
    )

    assert {:ok, :value2} = HydratingCache.get(pid, :key2)
  end

  test "can retrieve all values beside erroneous ones" do
    {:ok, pid} =
      HydratingCache.start_link(:test_service_get_all, [
        {"key1", {__MODULE__, :val_hydrating_function, [10]}, 10_00, :infinity},
        {"key2", {__MODULE__, :failval_hydrating_function, [20]}, 10_00, :infinity},
        {"key3", {__MODULE__, :val_hydrating_function, [30]}, 10_00, :infinity}
      ])

    assert [10, 30] = HydratingCache.get_all(pid)
  end

  test "Retrieving all values supports delayed values" do
    {:ok, pid} =
      HydratingCache.start_link(:test_service_get_all_delayed, [
        {"key1", {__MODULE__, :val_hydrating_function, [10]}, 10_000, :infinity},
        {"key2", {__MODULE__, :timed_hydrating_function, [50, 20]}, 10_000, :infinity},
        {"key3", {__MODULE__, :failval_hydrating_function, [30]}, 10_000, :infinity}
      ])

    assert [10, 20] = HydratingCache.get_all(pid)
  end

  def val_hydrating_function(value) do
    {:ok, value}
  end

  def failval_hydrating_function(value) do
    {:error, value}
  end

  def timed_hydrating_function(delay, value) do
    Process.sleep(delay)
    {:ok, value}
  end
end
