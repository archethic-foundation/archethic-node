defmodule Archethic.P2P.Message.DashboardDataTest do
  @moduledoc false

  alias Archethic.P2P.Message.DashboardData
  alias Archethic.P2P.Message

  use ExUnit.Case
  import ArchethicCase

  test "encode decode empty" do
    msg = %DashboardData{
      buckets: %{}
    }

    assert {^msg, <<>>} =
             msg
             |> Message.encode()
             |> Message.decode()
  end

  test "encode decode" do
    msg = %DashboardData{
      buckets: %{
        ~U[2023-11-23 17:00:00Z] => [{random_address(), 1_000_000_001}],
        ~U[2023-11-23 17:01:00Z] => [
          {random_address(), 1_000_000_002},
          {random_address(), 2_000_000_006}
        ],
        ~U[2023-11-23 17:02:00Z] => [],
        ~U[2023-11-23 17:03:00Z] => [
          {random_address(), 1_000_000_004},
          {random_address(), 2_000_000_008},
          {random_address(), 3_000_000_009}
        ]
      }
    }

    assert {^msg, <<>>} =
             msg
             |> Message.encode()
             |> Message.decode()
  end
end
