defmodule Archethic.Contracts.Interpreter.Library.Common.JsonTest do
  @moduledoc """
  Here we test the module within the action block. Because there is AST modification (such as keywords to maps)
  in the ActionInterpreter and we want to test the whole thing.
  """

  use ArchethicCase

  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.ActionInterpreter
  alias Archethic.Contracts.Interpreter.Library.Common.Json

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  doctest Json

  # ----------------------------------------
  describe "to_string/1" do
    test "should work with float" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content Json.to_string(1.0)
      end
      """

      assert %Transaction{data: %TransactionData{content: "1.0"}} = sanitize_parse_execute(code)
    end

    test "should work with integer" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content Json.to_string(1)
      end
      """

      assert %Transaction{data: %TransactionData{content: "1"}} = sanitize_parse_execute(code)
    end

    test "should work with string" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content Json.to_string("hello")
      end
      """

      assert %Transaction{data: %TransactionData{content: "\"hello\""}} =
               sanitize_parse_execute(code)
    end

    test "should work with list" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content Json.to_string([1,2,3])
      end
      """

      assert %Transaction{data: %TransactionData{content: "[1,2,3]"}} =
               sanitize_parse_execute(code)
    end

    test "should work with map" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content Json.to_string([foo: "bar"])
      end
      """

      assert %Transaction{data: %TransactionData{content: "{\"foo\":\"bar\"}"}} =
               sanitize_parse_execute(code)
    end

    test "should work with variable" do
      code = ~S"""
      actions triggered_by: transaction do
        variable = [foo: "bar"]
        Contract.set_content Json.to_string(variable)
      end
      """

      assert %Transaction{data: %TransactionData{content: "{\"foo\":\"bar\"}"}} =
               sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "is_valid?/1" do
    test "should work" do
      code = ~S"""
      actions triggered_by: transaction do
        x = Json.to_string(hello: "world", foo: "bar")
        if Json.is_valid?(x) do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end
  end

  defp sanitize_parse_execute(code, constants \\ %{}) do
    with {:ok, sanitized_code} <- Interpreter.sanitize_code(code),
         {:ok, _, action_ast} <- ActionInterpreter.parse(sanitized_code) do
      ActionInterpreter.execute(action_ast, constants)
    end
  end
end
