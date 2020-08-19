defmodule Uniris.UtilsTests do
  use ExUnit.Case
  doctest Uniris.Utils

  alias Uniris.Utils

  describe "time_offset/1 should return the number of milliseconds to reach an interval" do
    test "each minute" do
      current_time = DateTime.utc_now()
      shift = Utils.time_offset("* * * * * *")
      next_time = DateTime.add(current_time, shift)
      assert next_time.second == 0 or next_time.second == 59

      assert 0 == next_time.second

      if current_time.minute == 59 do
        assert next_time.minute == 0
      else
        assert next_time.minute == current_time.minute + 1
      end
    end

    test "each day" do
      current_time = DateTime.utc_now()
      shift = Utils.time_offset("* 0 * * * *")
      next_time = DateTime.add(current_time, shift)

      assert true =
               (next_time.hour == 0 and next_time.minute == 0 and next_time.second == 0) or
                 (next_time.hour == 23 and next_time.minute == 59 and next_time.second == 59)

      assert true ==
               (next_time.hour == 0 and next_time.minute == 0 and next_time.second == 0 and
                  next_time.day == current_time.day + 1) or
               (next_time.hour == 23 and next_time.minute == 59 and next_time.second == 59 and
                  next_time.day == current_time.day)
    end
  end
end
