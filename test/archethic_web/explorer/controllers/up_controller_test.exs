defmodule ArchethicWeb.Explorer.UpControllerTest do
  @moduledoc false
  use ArchethicCase
  use ArchethicWeb.ConnCase

  test "should return 503 when bootstrap is not over", %{conn: conn} do
    :persistent_term.put(:archethic_up, nil)

    conn = get(conn, "/up")

    assert "" = response(conn, 503)
  end

  test "should return 200 when bootstrap is over", %{conn: conn} do
    :persistent_term.put(:archethic_up, :up)

    conn = get(conn, "/up")

    assert "up" = response(conn, 200)
  end
end
