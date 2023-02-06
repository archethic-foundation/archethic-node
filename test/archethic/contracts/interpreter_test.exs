defmodule Archethic.Contracts.InterpreterTest do
  @moduledoc false
  use ArchethicCase

  alias Archethic.Contracts.Interpreter

  doctest Interpreter

  describe "version/1" do
    test "should return 0.0.1 if there is no interpreter tag" do
      code = ~s(some code)
      assert {{0, 0, 1}, ^code} = Interpreter.version(code)
    end

    test "should return the correct version if specified" do
      assert {{0, 0, 1}, "\n my_code"} = Interpreter.version(~s(@version "0.0.1"\n my_code))
      assert {{0, 1, 0}, " \n my_code"} = Interpreter.version(~s(@version "0.1.0" \n my_code))
      assert {{0, 1, 1}, ""} = Interpreter.version(~s(@version "0.1.1"))
      assert {{1, 0, 0}, _} = Interpreter.version(~s(@version "1.0.0"))
      assert {{1, 0, 1}, _} = Interpreter.version(~s(@version "1.0.1"))
      assert {{1, 1, 0}, _} = Interpreter.version(~s(@version "1.1.0"))
      assert {{1, 1, 1}, _} = Interpreter.version(~s(@version "1.1.1"))
    end

    test "should work even if there are some whitespaces" do
      assert {{0, 1, 0}, _} = Interpreter.version(~s(\n   \n   @version "0.1.0" \n  \n))
      assert {{1, 1, 2}, _} = Interpreter.version(~s(\n   \n   @version "1.1.2" \n  \n))
      assert {{3, 105, 0}, _} = Interpreter.version(~s(\n   \n   @version "3.105.0" \n  \n))
    end

    test "should raise if version is not formatted as expected" do
      assert_raise RuntimeError, fn ->
        Interpreter.version(~s(@version "0"))
      end

      assert_raise RuntimeError, fn ->
        Interpreter.version(~s(@version "1"))
      end

      assert_raise RuntimeError, fn ->
        Interpreter.version(~s(@version "0.0"))
      end

      assert_raise RuntimeError, fn ->
        Interpreter.version(~s(@version "1.1"))
      end

      assert_raise RuntimeError, fn ->
        Interpreter.version(~s(@version "0.0.0"))
      end

      assert_raise RuntimeError, fn ->
        Interpreter.version(~s(@version 1.1.1))
      end
    end
  end
end
