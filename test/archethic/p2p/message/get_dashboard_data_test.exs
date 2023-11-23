defmodule Archethic.P2P.Message.GetDashboardDataTest do
  @moduledoc false

  alias Archethic.P2P.Message.GetDashboardData
  alias Archethic.P2P.Message

  use ExUnit.Case

  test "encode decode since=nil" do
    msg = %GetDashboardData{since: nil}

    assert {^msg, <<>>} =
             msg
             |> Message.encode()
             |> Message.decode()
  end

  test "encode decode since=datetime" do
    msg = %GetDashboardData{since: DateTime.utc_now() |> DateTime.truncate(:second)}

    assert {^msg, <<>>} =
             msg
             |> Message.encode()
             |> Message.decode()
  end
end
