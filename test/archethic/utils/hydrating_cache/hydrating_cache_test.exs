defmodule HydratingCacheTest do
  alias Archethic.Utils.HydratingCache
  use ExUnit.Case
  require Logger

  test "If `key` is not associated with any function, return `{:error, :not_registered}`" do
    {:ok, pid} = HydratingCache.start_link(:test_service)
    assert HydratingCache.get(pid, "unexisting_key") == {:error, :not_registered}
  end

  test "If value stored, it is returned immediatly" do
    {:ok, pid} = HydratingCache.start_link(:test_service)

    result =
      HydratingCache.register_function(
        pid,
        fn ->
          {:ok, 1}
        end,
        "simple_func",
        10_000,
        15_000
      )

    assert result == :ok
    ## WAit a little to be sure value is registered and not being refreshed
    :timer.sleep(500)
    r = HydratingCache.get(pid, "simple_func", 10_000)
    assert r == {:ok, 1}
  end

  test "Hydrating function runs periodically" do
    {:ok, pid} = HydratingCache.start_link(:test_service)

    :persistent_term.put("test", 1)

    result =
      HydratingCache.register_function(
        pid,
        fn ->
          IO.puts("Hydrating function incrementing value")
          value = :persistent_term.get("test")
          value = value + 1
          :persistent_term.put("test", value)
          {:ok, value}
        end,
        "test_inc",
        1_000,
        50_000
      )

    assert result == :ok

    :timer.sleep(3000)
    {:ok, value} = HydratingCache.get(pid, "test_inc", 3000)

    assert value >= 3
  end

  test "Update hydrating function while another one is running returns new hydrating value from new function" do
    {:ok, pid} = HydratingCache.start_link(:test_service)

    result =
      HydratingCache.register_function(
        pid,
        fn ->
          :timer.sleep(5000)
          {:ok, 1}
        end,
        "test_reregister",
        10_000,
        50_000
      )

    assert result == :ok

    _result =
      HydratingCache.register_function(
        pid,
        fn ->
          {:ok, 2}
        end,
        "test_reregister",
        10_000,
        50_000
      )

    :timer.sleep(5000)
    {:ok, value} = HydratingCache.get(pid, "test_reregister", 4000)

    assert value == 2
  end

  test "Getting value while function is running and previous value is available returns value" do
    {:ok, pid} = HydratingCache.start_link(:test_service)

    _ =
      HydratingCache.register_function(
        pid,
        fn ->
          {:ok, 1}
        end,
        "test_reregister",
        40_000,
        50_000
      )

    _ =
      HydratingCache.register_function(
        pid,
        fn ->
          Logger.info("Hydrating function sleeping 5 secs")
          :timer.sleep(5000)
          {:ok, 2}
        end,
        "test_reregister",
        40_000,
        50_000
      )

    {:ok, value} = HydratingCache.get(pid, "test_reregister", 4000)

    assert value == 1
  end

  test "Two hydrating function can run at same time" do
    {:ok, pid} = HydratingCache.start_link(:test_service)

    _ =
      HydratingCache.register_function(
        pid,
        fn ->
          :timer.sleep(5000)
          {:ok, :result_timed}
        end,
        "timed_value",
        70_000,
        80_000
      )

    _ =
      HydratingCache.register_function(
        pid,
        fn ->
          {:ok, :result}
        end,
        "direct_value",
        70_000,
        80_000
      )

    ## We query the value with timeout smaller than timed function
    {:ok, _value} = HydratingCache.get(pid, "direct_value", 2000)
  end

  test "Querying key while first refreshed will block the calling process until refreshed and provide the value" do
    {:ok, pid} = HydratingCache.start_link(:test_service)

    _ =
      HydratingCache.register_function(
        pid,
        fn ->
          :timer.sleep(4000)
          {:ok, :valid_result}
        end,
        "delayed_result",
        70_000,
        80_000
      )

    ## We query the value with timeout smaller than timed function
    assert {:ok, :valid_result} = HydratingCache.get(pid, "delayed_result", 5000)
  end

  test "Querying key while first refreshed will block the calling process until timeout" do
    {:ok, pid} = HydratingCache.start_link(:test_service)

    _ =
      HydratingCache.register_function(
        pid,
        fn ->
          :timer.sleep(2000)
          {:ok, :valid_result}
        end,
        "delayed_result",
        70_000,
        80_000
      )

    ## We query the value with timeout smaller than timed function
    assert {:error, :timeout} = HydratingCache.get(pid, "delayed_result", 1000)
  end

  test "Multiple process can wait for a delayed value" do
    {:ok, pid} = HydratingCache.start_link(:test_service)

    _ =
      HydratingCache.register_function(
        pid,
        fn ->
          IO.puts("Hydrating function Sleeping 3 secs")
          :timer.sleep(3000)
          IO.puts("Hydrating function done")
          {:ok, :valid_result}
        end,
        "delayed_result",
        70_000,
        80_000
      )

    ## We query the value with timeout smaller than timed function
    results =
      Task.async_stream(1..10, fn _ -> HydratingCache.get(pid, "delayed_result", 4000) end)

    assert Enum.all?(results, fn
             {:ok, {:ok, :valid_result}} -> true
             other -> IO.puts("Unk #{inspect(other)}")
           end)
  end

  ## Resilience tests
  test "If hydrating function crash, key fsm will still be operationnal" do
    {:ok, pid} = HydratingCache.start_link(:test_service)

    _ =
      HydratingCache.register_function(
        pid,
        fn ->
          ## Exit hydrating function
          exit(1)
          {:ok, :badmatch}
        end,
        :key,
        70_000,
        80_000
      )

    :timer.sleep(1000)

    _ =
      HydratingCache.register_function(
        pid,
        fn ->
          ## Trigger badmatch
          {:ok, :value}
        end,
        :key,
        70_000,
        80_000
      )

    result = HydratingCache.get(pid, :key, 3000)
    assert result == {:ok, :value}
  end

  ## This could occur if hydrating function takes time to answer.
  ## In this case, getting the value would return the old value, unless too
  ## much time occur where it would be discarded because of ttl
  test "value gets discarded after some time" do
    {:ok, pid} = HydratingCache.start_link(:test_service)

    _ =
      HydratingCache.register_function(
        pid,
        fn ->
          case :persistent_term.get("flag", nil) do
            1 ->
              :timer.sleep(3_000)

            nil ->
              :persistent_term.put("flag", 1)
              {:ok, :value}
          end
        end,
        :key,
        500,
        1_000
      )

    :timer.sleep(1_100)
    result = HydratingCache.get(pid, :key, 3000)
    assert result == {:error, :discarded}
  end
end
