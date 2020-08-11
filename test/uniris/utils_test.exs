defmodule Uniris.UtilsTests do
  use ExUnit.Case
  doctest Uniris.Utils

  alias Uniris.Utils

  describe "time_offset/1 should return the number of milliseconds to reach an interval" do
    test "each minute" do
      current_time = DateTime.utc_now()
      shift = Utils.time_offset("* * * * * *")
      next_time = DateTime.add(current_time, shift)
      assert next_time.second == 0
      assert next_time.minute == current_time.minute + 1
    end

    test "each day" do
      current_time = DateTime.utc_now()
      shift = Utils.time_offset("* 0 * * * *")
      next_time = DateTime.add(current_time, shift)
      assert next_time.second == 0
      assert next_time.minute == 0
      assert next_time.hour == 0
      assert next_time.day == current_time.day + 1
    end
  end
end
