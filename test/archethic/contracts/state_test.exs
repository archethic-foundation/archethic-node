defmodule Archethic.Contracts.StateTest do
  alias Archethic.Contracts.State

  use ArchethicCase

  describe "to_utxo" do
    test "should return error if state is too big" do
      state = %{"key" => :crypto.strong_rand_bytes(280_000)}
      assert {:error, :state_too_big} = State.to_utxo(state)
    end
  end

  describe "to_utxo/from_utxo" do
    test "works with empty state" do
      state = %{}

      assert ^state =
               state
               |> State.to_utxo()
               |> elem(1)
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
               |> elem(1)
               |> State.from_utxo()
    end
  end
end
