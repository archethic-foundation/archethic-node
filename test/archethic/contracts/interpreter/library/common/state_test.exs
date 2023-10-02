defmodule Archethic.Contracts.Interpreter.Library.Common.StateTest do
  alias Archethic.Contracts.Interpreter.Library.Common.State

  use ArchethicCase
  use ExUnitProperties

  # ----------------------------------------
  describe "get/1 && set/2" do
    setup do
      # initiate a scope with an empty state
      Process.put(:scope, %{state: %{}})
      :ok
    end

    property "should be able to work together with any acceptable values" do
      check all(
              string <- StreamData.string(:utf8),
              int <- StreamData.integer(),
              float <- StreamData.float(),
              bool <- StreamData.boolean(),
              list <-
                StreamData.list_of(
                  StreamData.one_of([
                    StreamData.string(:utf8),
                    StreamData.boolean(),
                    StreamData.integer(),
                    StreamData.float()
                  ])
                ),
              map <-
                StreamData.map_of(
                  StreamData.one_of([
                    StreamData.string(:utf8),
                    StreamData.integer(),
                    StreamData.float()
                  ]),
                  StreamData.one_of([
                    StreamData.string(:utf8),
                    StreamData.boolean(),
                    StreamData.integer(),
                    StreamData.float()
                  ])
                )
            ) do
        test_values = [
          {"string", string},
          {"int", int},
          {"float", float},
          {"nil", nil},
          {"list", list},
          {"map", map},
          {"bool", bool}
        ]

        for {key, value} <- test_values do
          State.set(key, value)
        end

        for {key, value} <- test_values do
          assert value == State.get(key)
        end
      end
    end
  end

  describe "get/2" do
    setup do
      # initiate a scope with an empty state
      Process.put(:scope, %{state: %{}})
      :ok
    end

    test "should return the value if key is found" do
      State.set("existing key", 23)
      assert 23 == State.get("existing key", 42)
    end

    test "should return the default if key is not found" do
      assert 42 == State.get("not existing key", 42)
    end
  end

  describe "delete/1" do
    setup do
      # initiate a scope with an empty state
      Process.put(:scope, %{state: %{}})
      :ok
    end

    test "should delete the key" do
      State.set("key", 23)
      assert 23 == State.get("key")
      State.delete("key")
      assert nil == State.get("key")

      assert 0 =
               Process.get(:scope)
               |> Map.get(:state)
               |> map_size()
    end
  end
end
