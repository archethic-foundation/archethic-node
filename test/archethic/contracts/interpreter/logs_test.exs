defmodule Archethic.Contracts.Interpreter.LogsTest do
  alias Archethic.Contracts.Interpreter.Logs

  use ExUnit.Case

  describe "append/1 & all/0" do
    test "should return an empty list if no logs" do
      assert [] = Logs.all()
    end

    test "should return ordered logs" do
      Logs.append(1)
      Logs.append(2)
      Logs.append(3)
      Logs.append(4)
      assert [{%DateTime{}, 1}, {%DateTime{}, 2}, {%DateTime{}, 3}, {%DateTime{}, 4}] = Logs.all()
    end

    test "should accept any terms" do
      Logs.append(1.000001)
      Logs.append([1, 2, 3])
      Logs.append(foo: "bar")
      Logs.append(true)

      assert [
               {%DateTime{}, 1.000001},
               {%DateTime{}, [1, 2, 3]},
               {%DateTime{}, foo: "bar"},
               {%DateTime{}, true}
             ] = Logs.all()
    end
  end

  describe "reset/0" do
    Logs.append(1.000001)
    Logs.append([1, 2, 3])
    Logs.reset()
    Logs.append(foo: "bar")
    Logs.append(true)

    assert [
             {%DateTime{}, foo: "bar"},
             {%DateTime{}, true}
           ] = Logs.all()
  end
end
