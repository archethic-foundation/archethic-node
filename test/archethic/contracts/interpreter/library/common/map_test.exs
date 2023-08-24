defmodule Archethic.Contracts.Interpreter.Library.Common.MapTest do
  @moduledoc """
  Here we test the module within the action block. Because there is AST modification (such as keywords to maps)
  in the ActionInterpreter and we want to test the whole thing.
  """

  use ArchethicCase
  import ArchethicCase

  alias Archethic.Contracts.Interpreter.Library.Common.Map

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  doctest Map
  # ----------------------------------------
  describe "new/0" do
    test "should work" do
      code = ~s"""
      actions triggered_by: transaction do
        Contract.set_content Map.size(Map.new())
      end
      """

      assert %Transaction{data: %TransactionData{content: "0"}} = sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "size/1" do
    test "should work" do
      code = ~s"""
      actions triggered_by: transaction do
        Contract.set_content Map.size([one: 1, two: 2, three: 3])
      end
      """

      assert %Transaction{data: %TransactionData{content: "3"}} = sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "get/2" do
    test "should return value when key exist" do
      code = ~s"""
      actions triggered_by: transaction do
        numbers = [one: 1, two: 2, three: 3]
        Contract.set_content Map.get(numbers, "one")
      end
      """

      assert %Transaction{data: %TransactionData{content: "1"}} = sanitize_parse_execute(code)
    end

    test "should return nil when key not found" do
      code = ~s"""
      actions triggered_by: transaction do
        numbers = [one: 1, two: 2, three: 3]
        if nil == Map.get(numbers, "four") do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "get/3" do
    test "should return value when key exist" do
      code = ~s"""
      actions triggered_by: transaction do
        numbers = [one: 1, two: 2, three: 3]
        Contract.set_content Map.get(numbers, "one", 12)
      end
      """

      assert %Transaction{data: %TransactionData{content: "1"}} = sanitize_parse_execute(code)
    end

    test "should return default when key not found" do
      code = ~s"""
      actions triggered_by: transaction do
        numbers = [one: 1, two: 2, three: 3]
        Contract.set_content Map.get(numbers, "four", 4)
      end
      """

      assert %Transaction{data: %TransactionData{content: "4"}} = sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "set/3" do
    test "should work" do
      code = ~s"""
      actions triggered_by: transaction do
        numbers = [one: 1]
        numbers = Map.set(numbers, "two", 2)
        Contract.set_content Json.to_string(numbers)
      end
      """

      assert %Transaction{data: %TransactionData{content: "{\"one\":1,\"two\":2}"}} =
               sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "keys/1" do
    test "should work" do
      code = ~s"""
      actions triggered_by: transaction do
        numbers = [one: 1, two: 2]
        keys = Map.keys(numbers)
        Contract.set_content Json.to_string(keys)
      end
      """

      assert %Transaction{data: %TransactionData{content: "[\"one\",\"two\"]"}} =
               sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "values/1" do
    test "should work" do
      code = ~s"""
      actions triggered_by: transaction do
        numbers = [one: 1, two: 2]
        values = Map.values(numbers)
        Contract.set_content Json.to_string(values)
      end
      """

      assert %Transaction{data: %TransactionData{content: "[1,2]"}} = sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "delete/2" do
    test "should work" do
      code = ~s"""
      actions triggered_by: transaction do
        numbers = [one: 1, two: 2]
        values = Map.delete(numbers, "one")
        Contract.set_content Json.to_string(values)
      end
      """

      assert %Transaction{data: %TransactionData{content: "{\"two\":2}"}} =
               sanitize_parse_execute(code)
    end
  end
end
