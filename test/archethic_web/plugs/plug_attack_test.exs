defmodule ArchethicWeb.PlugAttackTest do
  use ArchethicWeb.ConnCase

  describe "plug attack should: " do
    test "return 403 Forbidden if the user makes more than 10 requests per second", %{conn: conn} do
      Enum.each(1..10, fn
        _ ->
          conn
          |> get("/up")
          |> response(503)
      end)

      conn = get(conn, "/up")
      assert response(conn, 403) =~ "Forbidden"
    end
  end
end
