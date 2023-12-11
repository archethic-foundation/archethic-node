defmodule Archethic.UtilsTest do
  @moduledoc false
  use ExUnit.Case

  alias Archethic.P2P.Node
  alias Archethic.Utils

  doctest Utils

  setup do
    Registry.start_link(keys: :unique, name: Archethic.RunExclusiveRegistry)
    :ok
  end

  test "run_exclusive/2 should run a function only once" do
    me = self()

    Task.async_stream(0..10, fn _ ->
      Utils.run_exclusive(:foo, fn _ ->
        send(me, :bar)

        # simulate some execution time
        Process.sleep(10)
      end)
    end)
    |> Stream.run()

    assert_receive :bar, 100
    refute_receive :bar, 100
  end

  test "run_exclusive/2 should not send any message" do
    me = self()

    Utils.run_exclusive(:foo, fn _ ->
      send(me, :bar)

      # simulate some execution time
      Process.sleep(10)
    end)

    assert_receive :bar, 100
    refute_receive _, 100
  end

  describe "get_current_time_for_interval/2" do
    test "should return a value truncated to the minute (* minute)" do
      now = DateTime.utc_now()
      now_minus_1 = now |> DateTime.add(-1, :minute)
      datetime = Utils.get_current_time_for_interval("* * * * *", false)

      assert %DateTime{second: 0, microsecond: {0, 0}} = datetime
      assert DateTime.compare(datetime, now) == :lt
      assert DateTime.compare(datetime, now_minus_1) == :gt
    end

    test "should return a value truncated to the minute (*/5 minute)" do
      now = DateTime.utc_now()
      now_minus_1 = now |> DateTime.add(-5, :minute)
      datetime = Utils.get_current_time_for_interval("*/5 * * * *", false)

      assert %DateTime{minute: minute, second: 0, microsecond: {0, 0}} = datetime
      assert 0 == rem(minute, 5)
      assert DateTime.compare(datetime, now) == :lt
      assert DateTime.compare(datetime, now_minus_1) == :gt
    end

    test "should return a value truncated to the second (* second)" do
      now = DateTime.utc_now()
      now_minus_1 = now |> DateTime.add(-1, :second)
      datetime = Utils.get_current_time_for_interval("* * * * *", true)

      assert %DateTime{microsecond: {0, 0}} = datetime
      assert DateTime.compare(datetime, now) == :lt
      assert DateTime.compare(datetime, now_minus_1) == :gt
    end

    test "should return a value truncated to the second (*/2 second)" do
      now = DateTime.utc_now()
      now_minus_1 = now |> DateTime.add(-2, :second)
      datetime = Utils.get_current_time_for_interval("*/2 * * * *", true)

      assert %DateTime{second: second, microsecond: {0, 0}} = datetime
      assert 0 == rem(second, 2)
      assert DateTime.compare(datetime, now) == :lt
      assert DateTime.compare(datetime, now_minus_1) == :gt
    end
  end
end
