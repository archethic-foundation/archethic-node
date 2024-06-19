defmodule Archethic.Contracts.Interpreter.Library.Common.JsonTest do
  @moduledoc """
  Here we test the module within the action block. Because there is AST modification (such as keywords to maps)
  in the ActionInterpreter and we want to test the whole thing.
  """

  use ArchethicCase
  import ArchethicCase

  alias Archethic.Contracts.Interpreter.Library.Common.Json

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  doctest Json

  # ----------------------------------------
  describe "to_string/1" do
    test "should work with float" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content Json.to_string(0.1)
      end
      """

      assert {%Transaction{data: %TransactionData{content: "0.1"}}, _state} =
               sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content Json.to_string(1.0)
      end
      """

      assert {%Transaction{data: %TransactionData{content: "1"}}, _state} =
               sanitize_parse_execute(code)
    end

    test "should work with integer" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content Json.to_string(1)
      end
      """

      assert {%Transaction{data: %TransactionData{content: "1"}}, _state} =
               sanitize_parse_execute(code)
    end

    test "should work with string" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content Json.to_string("hello")
      end
      """

      assert {%Transaction{data: %TransactionData{content: "\"hello\""}}, _state} =
               sanitize_parse_execute(code)
    end

    test "should work with list" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content Json.to_string([1,2,3])
      end
      """

      assert {%Transaction{data: %TransactionData{content: "[1,2,3]"}}, _state} =
               sanitize_parse_execute(code)
    end

    test "should work with map" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content Json.to_string([foo: "bar"])
      end
      """

      assert {%Transaction{data: %TransactionData{content: "{\"foo\":\"bar\"}"}}, _state} =
               sanitize_parse_execute(code)
    end

    test "should work with variable" do
      code = ~S"""
      actions triggered_by: transaction do
        variable = [foo: "bar"]
        Contract.set_content Json.to_string(variable)
      end
      """

      assert {%Transaction{data: %TransactionData{content: "{\"foo\":\"bar\"}"}}, _state} =
               sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "parse/1" do
    test "should work with string" do
      code = ~S"""
      actions triggered_by: transaction do
        x = Json.parse("{ \"hello\": \"world\", \"foo\": \"bar\"}")
        Contract.set_content x.hello
      end
      """

      assert {%Transaction{data: %TransactionData{content: "world"}}, _state} =
               sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content Json.parse("\"Whoopi Goldberg\"")
      end
      """

      assert {%Transaction{data: %TransactionData{content: "Whoopi Goldberg"}}, _state} =
               sanitize_parse_execute(code)
    end

    test "should work with integer" do
      code = ~S"""
      actions triggered_by: transaction do
        x = Json.parse("{ \"integer\": 42, \"foo\": \"bar\"}")
        Contract.set_content x.integer
      end
      """

      assert {%Transaction{data: %TransactionData{content: "42"}}, _state} =
               sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        if Json.parse("42") == 42 do
          Contract.set_content "ok"
        end
      end
      """

      assert {%Transaction{data: %TransactionData{content: "ok"}}, _state} =
               sanitize_parse_execute(code)
    end

    test "should work with floats" do
      code = ~S"""
      actions triggered_by: transaction do
        x = Json.parse("{ \"f\": 42.1}")
        Contract.set_content x.f
      end
      """

      assert {%Transaction{data: %TransactionData{content: "42.1"}}, _state} =
               sanitize_parse_execute(code)
    end

    test "should work with list" do
      code = ~S"""
      actions triggered_by: transaction do
        x = Json.parse("{ \"list\": [1,2,3], \"foo\": \"bar\"}")
        Contract.set_content Json.to_string(x.list)
      end
      """

      assert {%Transaction{data: %TransactionData{content: "[1,2,3]"}}, _state} =
               sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        x = Json.parse("[1,2,3]")
        if List.at(x, 0) == 1 do
          Contract.set_content "ok"
        end
      end
      """

      assert {%Transaction{data: %TransactionData{content: "ok"}}, _state} =
               sanitize_parse_execute(code)
    end

    test "should work with map" do
      code = ~S"""
      actions triggered_by: transaction do
        x = Json.parse("{ \"map\": {\"foo\" : \"bar\"} }")
        Contract.set_content Json.to_string(x.map)
      end
      """

      assert {%Transaction{data: %TransactionData{content: "{\"foo\":\"bar\"}"}}, _state} =
               sanitize_parse_execute(code)
    end

    test "should work with variable" do
      code = ~S"""
      actions triggered_by: transaction do
        data = "{ \"list\": [1,2,3], \"foo\": \"bar\"}"
        x = Json.parse(data)
        Contract.set_content Json.to_string(x.list)
      end
      """

      assert {%Transaction{data: %TransactionData{content: "[1,2,3]"}}, _state} =
               sanitize_parse_execute(code)
    end

    test "should work with affected variable" do
      code = ~S"""
      actions triggered_by: transaction do
        x = Json.parse("{ \"list\": [1,2,3], \"foo\": \"bar\"}")
        y = x.list
        Contract.set_content Json.to_string(y)
      end
      """

      assert {%Transaction{data: %TransactionData{content: "[1,2,3]"}}, _state} =
               sanitize_parse_execute(code)
    end

    test "should not parse if parameter is not a string" do
      code = ~S"""
      actions triggered_by: transaction do
        Json.parse(key: "value")
      end
      """

      assert {:error, _, _} = sanitize_parse_execute(code)
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

      assert {%Transaction{data: %TransactionData{content: "ok"}}, _state} =
               sanitize_parse_execute(code)
    end
  end
end
