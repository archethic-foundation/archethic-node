defmodule Archethic.Contracts.Interpreter.FunctionInterpreterTest do
  @moduledoc false

  use ArchethicCase
  use ExUnitProperties

  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.FunctionKeys
  alias Archethic.Contracts.Interpreter.FunctionInterpreter

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
               |> Interpreter.sanitize_code(check_legacy?: false)
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
               |> Interpreter.sanitize_code(check_legacy?: false)
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
               |> Interpreter.sanitize_code(check_legacy?: false)
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
               |> Interpreter.sanitize_code(check_legacy?: false)
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
               |> Interpreter.sanitize_code(check_legacy?: false)
               |> elem(1)
               |> FunctionInterpreter.parse([])

      code = ~S"""
      export fun test_public do
        Contract.set_content "hello"
      end
      """

      assert {:error, _, "Write contract functions are not allowed in custom functions"} =
               code
               |> Interpreter.sanitize_code(check_legacy?: false)
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
               |> Interpreter.sanitize_code(check_legacy?: false)
               |> elem(1)
               |> FunctionInterpreter.parse([])
    end

    test "should not be able to use IO functions in public function with dot access" do
      code = ~S"""
      export fun test do
       Chain.get_transaction("hello").content
      end
      """

      assert {:error, _, "IO function calls not allowed in public functions"} =
               code
               |> Interpreter.sanitize_code(check_legacy?: false)
               |> elem(1)
               # mark function as declared
               |> FunctionInterpreter.parse(
                 FunctionKeys.new()
                 |> FunctionKeys.add_public("hello", 0)
               )
    end

    test "should not be able to use IO functions in public function with dynamic access" do
      code = ~S"""
      export fun test do
       Chain.get_transaction("hello")["content"]
      end
      """

      assert {:error, _, "IO function calls not allowed in public functions"} =
               code
               |> Interpreter.sanitize_code(check_legacy?: false)
               |> elem(1)
               # mark function as declared
               |> FunctionInterpreter.parse(
                 FunctionKeys.new()
                 |> FunctionKeys.add_public("hello", 0)
               )
    end

    test "should return an error if module is unknown" do
      code = ~S"""
      export fun test_public do
        Hello.world()
      end
      """

      assert {:error, _, "Module Hello does not exists"} =
               code
               |> Interpreter.sanitize_code(check_legacy?: false)
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
               |> Interpreter.sanitize_code(check_legacy?: false)
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
               |> Interpreter.sanitize_code(check_legacy?: false)
               |> elem(1)
               |> FunctionInterpreter.parse([])

      code = ~S"""
      export fun test_public do
        Chain.get_burn_address()
      end
      """

      assert {:ok, _, _, _} =
               code
               |> Interpreter.sanitize_code(check_legacy?: false)
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
               |> Interpreter.sanitize_code(check_legacy?: false)
               |> elem(1)
               |> FunctionInterpreter.parse(%{})
    end

    test "should be able to call declared public function from private function" do
      code = ~S"""
      fun test do
       hello()
      end
      """

      assert {:ok, "test", _, _} =
               code
               |> Interpreter.sanitize_code(check_legacy?: false)
               |> elem(1)
               # mark function as declared
               |> FunctionInterpreter.parse(
                 FunctionKeys.new()
                 |> FunctionKeys.add_public("hello", 0)
               )
    end

    test "should not be able to call declared private function from private function" do
      code = ~S"""
      fun test do
       hello()
      end
      """

      assert {:error, _, "not allowed to call private function from a private function"} =
               code
               |> Interpreter.sanitize_code(check_legacy?: false)
               |> elem(1)
               # mark function as declared
               |> FunctionInterpreter.parse(
                 FunctionKeys.new()
                 |> FunctionKeys.add_private("hello", 0)
               )
    end

    test "should not be able to call declared function from public function" do
      code = ~S"""
      export fun im_public() do
       hello()
      end
      """

      assert {:error, _, "not allowed to call function from public function"} =
               code
               |> Interpreter.sanitize_code(check_legacy?: false)
               |> elem(1)
               # mark function as declared
               |> FunctionInterpreter.parse(
                 FunctionKeys.new()
                 |> FunctionKeys.add_public("hello", 0)
               )
    end

    test "should be able to call throw" do
      code = ~S"""
      export fun im_public() do
       throw code: 123, message: "throw"
      end
      """

      assert {:ok, _, _, _} =
               code
               |> Interpreter.sanitize_code(check_legacy?: false)
               |> elem(1)
               # mark function as declared
               |> FunctionInterpreter.parse(FunctionKeys.new())
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
        |> Interpreter.sanitize_code(check_legacy?: false)
        |> elem(1)
        |> FunctionInterpreter.parse([])

      fun2 = ~S"""
      fun test() do
        hello()
      end
      """

      {:ok, "test", [], ast_test} =
        fun2
        |> Interpreter.sanitize_code(check_legacy?: false)
        |> elem(1)
        # pass allowed function
        |> FunctionInterpreter.parse(
          FunctionKeys.new()
          |> FunctionKeys.add_public("hello", 0)
        )

      function_constant = %{:functions => %{{"hello", 0} => %{args: [], ast: ast_hello}}}

      assert Decimal.eq?(4, FunctionInterpreter.execute(ast_test, function_constant))
    end

    test "should be able to execute function with arg" do
      fun = ~S"""
      fun test(var1) do
        var1
      end
      """

      {:ok, "test", ["var1"], ast_fun} =
        fun
        |> Interpreter.sanitize_code(check_legacy?: false)
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
        |> Interpreter.sanitize_code(check_legacy?: false)
        |> elem(1)
        # pass allowed function
        |> FunctionInterpreter.parse([])

      assert Decimal.eq?(
               12,
               FunctionInterpreter.execute(ast_fun, %{}, ["var1", "var2"], [4, 8])
             )
    end
  end
end
