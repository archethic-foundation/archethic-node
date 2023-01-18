defmodule ArchethicWeb.PlugThrottleByIPTest do
  use ArchethicWeb.ConnCase

  use ArchethicCase, async: false

  describe "plug attack should return forbidden when the user makes more than the authorized number of requests " do
    @tag ratelimit: true
    test "within timeframe with the same ip",
         %{conn: conn} do
      limit = Application.get_env(:archethic, :throttle)[:by_ip][:limit] + 1

      is_rate_limited? =
        Task.async_stream(
          1..limit,
          fn n ->
            conn = get(conn, "/transaction/#{n}")
            conn.status
          end,
          ordered: false
        )
        |> Enum.reduce_while(false, fn
          {:ok, 429}, _acc -> {:halt, true}
          _, acc -> {:cont, acc}
        end)

      assert is_rate_limited?
    end
  end
end
