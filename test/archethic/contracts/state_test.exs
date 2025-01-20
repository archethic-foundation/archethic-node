defmodule Archethic.Contracts.Contract.StateTest do
  alias Archethic.Contracts.Contract.State

  use ArchethicCase

  describe "serialization/deserialization" do
    test "should deserialize when protocol_version < 9" do
      state = complex_state()

      assert {^state, <<>>} =
               state
               |> State.serialize(8)
               |> State.deserialize(8)
    end

    test "should serialize/deserialize when protocol_version >=9" do
      state = complex_state()

      assert {^state, <<>>} =
               state
               |> State.serialize(9)
               |> State.deserialize(9)
    end
  end

  describe "format/1" do
    test "should return a valid JSON prettified" do
      state = complex_state()

      assert {:ok, _} = State.format(state) |> Jason.decode()
    end
  end

  defp complex_state() do
    %{
      "foo" => "bar",
      "nil" => nil,
      "int" => 42,
      "list" => [1, 2, 3],
      "emptystr" => "",
      "emptymap" => %{},
      "mapwithcomplexkeys" => %{
        1 => 1,
        [2, 3] => 4,
        %{} => 5,
        true => false
      },
      "nested" => %{
        "list" => [
          [
            4,
            false,
            [
              5,
              %{
                "hello" => "world"
              }
            ],
            "6"
          ],
          23,
          []
        ]
      }
    }
  end
end
