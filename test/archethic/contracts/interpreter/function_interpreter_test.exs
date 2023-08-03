defmodule Archethic.Contracts.Interpreter.FunctionInterpreterTest do
  @moduledoc false

  use ArchethicCase
  use ExUnitProperties

  alias Archethic.Contracts.Interpreter.FunctionInterpreter
  alias Archethic.Contracts.Interpreter

  # ----------------------------------------------
  # parse/2
  # ----------------------------------------------
  describe "parse/2" do
    test "should be able to parse a private function" do
      code = ~S"""
      fun test_private do

      end
      """

      assert {:ok, "test_private", _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> FunctionInterpreter.parse([])
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
               |> FunctionInterpreter.parse([])
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
               |> FunctionInterpreter.parse([])
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
               |> FunctionInterpreter.parse([])
    end

    test "should not be able to use non-whitelisted modules" do
      code = ~S"""
      fun test_private do
        Contract.set_content "hello"
      end
      """

      assert {:error, _, "Write contract functions are not allowed in custom functions"} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> FunctionInterpreter.parse([])

      code = ~S"""
      export fun test_public do
        Contract.set_content "hello"
      end
      """

      assert {:error, _, "Write contract functions are not allowed in custom functions"} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> FunctionInterpreter.parse([])
    end

    test "should not be able to use IO functions in public function" do
      code = ~S"""
      export fun test_public do
        Chain.get_genesis_address("hello")
      end
      """

      assert {:error, _, "IO function calls not allowed in public functions"} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> FunctionInterpreter.parse([])
    end

    test "should return an error if module is unknown" do
      code = ~S"""
      export fun test_public do
        Hello.world()
      end
      """

      assert {:error, _, "Module Hello not found"} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> FunctionInterpreter.parse([])
    end

    test "should be able to use IO functions in private function" do
      code = ~S"""
      fun test_private do
        Chain.get_genesis_address("hello")
      end
      """

      assert {:ok, _, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> FunctionInterpreter.parse([])
    end

    test "should be able to parse public function when a module's function is not IO" do
      code = ~S"""
      fun test do
       Json.to_string "[1,2,3]"
      end
      """

      assert {:ok, "test", [], _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> FunctionInterpreter.parse([])

      code = ~S"""
      export fun test_public do
        Chain.get_burn_address()
      end
      """

      assert {:ok, _, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> FunctionInterpreter.parse([])
    end

    test "should not be able to call non declared function" do
      code = ~S"""
      fun test do
       hello()
      end
      """

      assert {:error, _, "The function hello/0 does not exist"} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> FunctionInterpreter.parse([])
    end

    test "should be able to call declared public function from private function" do
      code = ~S"""
      fun test do
       hello()
      end
      """

      assert {:ok, "test", _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               # mark function as declared
               |> FunctionInterpreter.parse([{"hello", 0, :public}])
    end

    test "should not be able to call declared private function from private function" do
      code = ~S"""
      fun test do
       hello()
      end
      """

      assert {:error, _, "not allowed to call private function from a private function"} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               # mark function as declared
               |> FunctionInterpreter.parse([{"hello", 0, :private}])
    end

    test "should not be able to call declared function from public function" do
      code = ~S"""
      export fun im_public() do
       hello()
      end
      """

      assert {:error, _, "not allowed to call function from public function"} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               # mark function as declared
               |> FunctionInterpreter.parse([{"hello", 0, :public}])
    end

    test "should not be able to call declared function from public function" do
      code = ~S"""
      export fun im_public() do
       hello()
      end
      """

      assert {:error, _, "not allowed to call function from public function"} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               # mark function as declared
               |> FunctionInterpreter.parse([{"hello", 0}])
    end
  end

  describe "execute/2" do
    test "should be able to execute function without args" do
      fun1 = ~S"""
        export fun hello do
          1 + 3
        end
      """

      {:ok, "hello", [], ast_hello} =
        fun1
        |> Interpreter.sanitize_code()
        |> elem(1)
        |> FunctionInterpreter.parse([])

      fun2 = ~S"""
      fun test() do
        hello()
      end
      """

      {:ok, "test", [], ast_test} =
        fun2
        |> Interpreter.sanitize_code()
        |> elem(1)
        # pass allowed function
        |> FunctionInterpreter.parse([{"hello", 0, :public}])

      function_constant = %{:functions => %{{"hello", 0} => %{args: [], ast: ast_hello}}}

      assert 4.0 = FunctionInterpreter.execute(ast_test, function_constant)
    end

    test "should be able to execute function with arg" do
      fun = ~S"""
      fun test(var1) do
        var1
      end
      """

      {:ok, "test", ["var1"], ast_fun} =
        fun
        |> Interpreter.sanitize_code()
        |> elem(1)
        # pass allowed function
        |> FunctionInterpreter.parse([])

      assert "BOB" = FunctionInterpreter.execute(ast_fun, %{}, ["var1"], ["BOB"])
    end

    test "should be able to execute function with multiple args" do
      fun = ~S"""
      fun test(var1, var2) do
        var1 + var2
      end
      """

      {:ok, "test", ["var1", "var2"], ast_fun} =
        fun
        |> Interpreter.sanitize_code()
        |> elem(1)
        # pass allowed function
        |> FunctionInterpreter.parse([])

      assert 12.0 == FunctionInterpreter.execute(ast_fun, %{}, ["var1", "var2"], [4, 8])
    end
  end
end
