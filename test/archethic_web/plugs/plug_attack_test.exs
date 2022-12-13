defmodule ArchethicWeb.PlugAttackTest do
  use ArchethicWeb.ConnCase

  use ArchethicCase, async: false

  @tag ratelimit: true
  describe "plug attack should: " do
    test "return 403 Forbidden if the user makes more than the authorized number of requests within timeframe",
         %{conn: conn} do
      is_rate_limited? =
        Task.async_stream(1..1_000, fn _ ->
          conn = get(conn, "/up")
          conn.status
        end)
        |> Enum.reduce_while(false, fn
          {:ok, 403}, _acc -> {:halt, true}
          _, acc -> {:cont, acc}
        end)

      assert is_rate_limited?
    end
  end
end
