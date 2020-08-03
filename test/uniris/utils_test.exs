defmodule Uniris.UtilsTests do
  use ExUnit.Case
  doctest Uniris.Utils

  alias Uniris.Utils

  describe "time_offset/1 should return the number of milliseconds to reach an interval" do
    test "each 20 seconds" do
      current_time = DateTime.utc_now()
      shift = Utils.time_offset(20_000)
      next_time = DateTime.add(current_time, trunc(shift / 1000))
      assert rem(next_time.second, 20) == 0
    end

    test "each minute" do
      current_time = DateTime.utc_now()
      shift = Utils.time_offset(60_000)
      next_time = DateTime.add(current_time, trunc(shift / 1000))
      assert next_time.second == 0
      assert next_time.minute == DateTime.add(current_time, 60).minute
    end

    test "each day" do
      current_time = DateTime.utc_now()
      shift = Utils.time_offset(86_400_000)
      next_time = DateTime.add(current_time, trunc(shift / 1000))
      assert next_time.second == 0
      assert next_time.day == DateTime.add(current_time, 86_400).day
    end
  end
end
