defmodule Archethic.Contracts.Interpreter.FunctionKeysTest do
  @moduledoc false

  use ArchethicCase

  alias Archethic.Contracts.Interpreter.FunctionKeys

  test "add_public/3 and add_private/3 should add function in map" do
    function_keys =
      %{}
      |> FunctionKeys.add_private("private_function", 0)
      |> FunctionKeys.add_public("public_function", 1)
      |> FunctionKeys.add_private("private_function", 1)

    assert %{
             {"private_function", 0} => :private,
             {"private_function", 1} => :private,
             {"public_function", 1} => :public
           } = function_keys
  end

  test "new/0 should return an empty map" do
    assert %{} = FunctionKeys.new()
  end

  describe "exist?/3" do
    test "should return true if function exists for arity" do
      function_keys = %{{"function", 1} => :private, {"other_function", 0} => :private}
      assert FunctionKeys.exist?(function_keys, "function", 1)
    end

    test "should return false if function doesn't exist for arity" do
      function_keys = %{{"function", 1} => :private, {"other_function", 0} => :private}
      refute FunctionKeys.exist?(function_keys, "function", 0)
    end
  end

  describe "private?/3" do
    test "should return true if function is private" do
      function_keys = %{{"function", 1} => :private, {"other_function", 0} => :private}
      assert FunctionKeys.private?(function_keys, "function", 1)
    end

    test "should return false if function is not private" do
      function_keys = %{{"function", 1} => :public, {"other_function", 0} => :private}
      refute FunctionKeys.private?(function_keys, "function", 1)
    end

    test "should raise an error if function doesn't exist" do
      function_keys = %{{"function", 1} => :public, {"other_function", 0} => :private}
      assert_raise(KeyError, fn -> FunctionKeys.private?(function_keys, "function", 0) end)
    end
  end
end
