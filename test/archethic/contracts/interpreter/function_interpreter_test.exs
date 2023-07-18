defmodule(Archethic.Contracts.Interpreter.FunctionInterpreterTest) do
  @moduledoc false

  use ArchethicCase
  use ExUnitProperties

  import ArchethicCase

  alias Archethic.Contracts.Interpreter.FunctionInterpreter
  alias Archethic.Contracts.Interpreter
  # ----------------------------------------------
  # parse/1
  # ----------------------------------------------
  describe "parse/1" do
    test "should be able to parse a private function" do
      code = ~S"""
      fun test_private do

      end
      """

      assert {:ok, "test_private", _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> FunctionInterpreter.parse()
    end

    test "should be able to parse a public function" do
      code = ~S"""
      export fun test_public do

      end
      """

      assert {:ok, "test_public", _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> FunctionInterpreter.parse()
    end

    test "should be able to parse a private function with arguments" do
      code = ~S"""
      fun test_private(arg1, arg2) do

      end
      """

      assert {:ok, "test_private", ["arg1", "arg2"], _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> FunctionInterpreter.parse()
    end

    test "should be able to parse a public function with arguments" do
      code = ~S"""
      export fun test_public(arg1, arg2) do

      end
      """

      assert {:ok, "test_public", ["arg1", "arg2"], _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> FunctionInterpreter.parse()
    end

    test "should not be able to use non-whitelisted modules" do
      code = ~S"""
      fun test_private do
        Contract.set_content "hello"
      end
      """

      assert {:error, _, "Contract is not allowed in function"} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> FunctionInterpreter.parse()
    end

    test "should be able to parse when there is whitelisted module" do
      code = ~S"""
      fun test do
       Json.to_string "[1,2,3]"
      end
      """

      assert {:ok, "test", [], _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> FunctionInterpreter.parse()
    end
  end
end
