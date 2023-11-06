defmodule Archethic.Contracts.Contract.StateTest do
  alias Archethic.Contracts.Contract.State

  use ArchethicCase

  describe "serialization/deserialization" do
    test "should work" do
      state = complex_state()

      assert {^state, <<>>} =
               state
               |> State.serialize()
               |> State.deserialize()
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
