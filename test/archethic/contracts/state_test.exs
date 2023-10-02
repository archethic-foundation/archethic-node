defmodule Archethic.Contracts.StateTest do
  alias Archethic.Contracts.State

  use ArchethicCase

  describe "to_utxo/from_utxo" do
    test "works with empty state" do
      state = %{}

      assert ^state =
               state
               |> State.to_utxo()
               |> State.from_utxo()
    end

    test "works with complex state" do
      state = %{
        "foo" => "bar",
        "int" => 42,
        "list" => [1, 2, 3],
        "nested" => %{
          "list" => [
            [
              4,
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

      assert ^state =
               state
               |> State.to_utxo()
               |> State.from_utxo()
    end
  end
end
