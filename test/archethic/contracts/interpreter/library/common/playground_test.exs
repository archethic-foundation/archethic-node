defmodule Archethic.Contracts.Interpreter.Library.Common.PlaygroundTest do
  use ArchethicCase

  alias Archethic.Contracts.Interpreter.Library.Common.Playground
  alias Archethic.Contracts.Interpreter.Logs

  doctest Playground

  describe "print/1" do
    test "should write strings in the process" do
      Playground.print("Hello")
      Playground.print("World")
      Playground.print("Foo Bar")

      assert [
               {%DateTime{}, "Hello"},
               {%DateTime{}, "World"},
               {%DateTime{}, "Foo Bar"}
             ] = Logs.all()
    end

    test "should write terms in the process" do
      Playground.print([1, 2, 3])
      Playground.print(foo: "bar", key: 42)
      Playground.print(true)
      Playground.print(1.203)

      assert [
               {%DateTime{}, [1, 2, 3]},
               {%DateTime{}, foo: "bar", key: 42},
               {%DateTime{}, true},
               {%DateTime{}, 1.203}
             ] = Logs.all()
    end
  end
end
