defmodule Archethic.Utils.DistinctEffectWorkerTest do
  use ExUnit.Case, async: false

  alias Archethic.Utils.DistinctEffectWorker

  setup do
    Registry.start_link(keys: :unique, name: Archethic.Utils.DistinctEffectWorkerRegistry)
    :ok
  end

  test "should be able to concurrently call the same effect and only 1 is triggered" do
    me = self()

    effect_fn = fn :hello ->
      send(me, :hello)
      Process.sleep(20)
    end

    :ok = DistinctEffectWorker.run(:hello, effect_fn)
    :ok = DistinctEffectWorker.run(:hello, effect_fn)
    :ok = DistinctEffectWorker.run(:hello, effect_fn)
    :ok = DistinctEffectWorker.run(:hello, effect_fn)

    assert 1 = Registry.count(Archethic.Utils.DistinctEffectWorkerRegistry)

    assert_receive :hello, 100
    refute_receive :hello, 200

    assert 0 = Registry.count(Archethic.Utils.DistinctEffectWorkerRegistry)
  end

  test "should be able to use default next_fn" do
    me = self()

    # the default next_fn will remove dups
    next_fn = &DistinctEffectWorker.default_next_fn/2

    effect_fn = fn i -> send(me, {:hello, i}) end

    :ok = DistinctEffectWorker.run(:hello, effect_fn, next_fn, [1, 2, 3])
    :ok = DistinctEffectWorker.run(:hello, effect_fn, next_fn, [4, 3, 2])

    assert 1 = Registry.count(Archethic.Utils.DistinctEffectWorkerRegistry)

    assert_receive {:hello, 1}, 100
    assert_receive {:hello, 2}, 100
    assert_receive {:hello, 3}, 100
    assert_receive {:hello, 4}, 100
    refute_receive _, 200

    assert 0 = Registry.count(Archethic.Utils.DistinctEffectWorkerRegistry)
  end

  test "should be able to use custom next_fn" do
    me = self()

    next_fn = fn inputs_to_process, _inputs_processed ->
      inputs_to_process
    end

    effect_fn = fn i -> send(me, {:hello, i}) end

    :ok = DistinctEffectWorker.run(:hello, effect_fn, next_fn, [1, 2, 3])
    :ok = DistinctEffectWorker.run(:hello, effect_fn, next_fn, [4, 3, 2])

    assert 1 = Registry.count(Archethic.Utils.DistinctEffectWorkerRegistry)

    assert_receive {:hello, 1}, 100
    assert_receive {:hello, 2}, 100
    assert_receive {:hello, 3}, 100
    assert_receive {:hello, 4}, 100
    assert_receive {:hello, 3}, 100
    assert_receive {:hello, 2}, 100
    refute_receive _, 200

    assert 0 = Registry.count(Archethic.Utils.DistinctEffectWorkerRegistry)
  end

  test "should be able run different effects concurrently" do
    me = self()

    effect1_fn = fn _ -> send(me, :effect1) end
    effect2_fn = fn _ -> send(me, :effect2) end

    :ok = DistinctEffectWorker.run(:foo, effect1_fn)
    :ok = DistinctEffectWorker.run(:bar, effect2_fn)

    assert 2 = Registry.count(Archethic.Utils.DistinctEffectWorkerRegistry)

    assert_receive :effect1, 100
    assert_receive :effect2, 100
    refute_receive _, 200

    assert 0 = Registry.count(Archethic.Utils.DistinctEffectWorkerRegistry)
  end
end
