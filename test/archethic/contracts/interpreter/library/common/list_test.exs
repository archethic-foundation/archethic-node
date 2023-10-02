defmodule Archethic.Contracts.Interpreter.Library.Common.ListTest do
  @moduledoc """
  Here we test the module within the action block. Because there is AST modification (such as keywords to maps)
  in the ActionInterpreter and we want to test the whole thing.
  """

  use ArchethicCase
  import ArchethicCase

  alias Archethic.Contracts.Interpreter.Library.Common.List

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  doctest List

  # ----------------------------------------
  describe "at/2" do
    test "should work" do
      code = ~s"""
      actions triggered_by: transaction do
        list = ["Jennifer", "John", "Jean", "Julie"]
        Contract.set_content List.at(list, 2)
      end
      """

      assert {%Transaction{data: %TransactionData{content: "Jean"}}, _state} =
               sanitize_parse_execute(code)
    end

    test "should work with maths (because bigint)" do
      code = ~s"""
      actions triggered_by: transaction do
        list = ["Jennifer", "John", "Jean", "Julie"]
        Contract.set_content List.at(list, 1+1)
      end
      """

      assert {%Transaction{data: %TransactionData{content: "Jean"}}, _state} =
               sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "size/1" do
    test "empty list should return 0" do
      code = ~s"""
      actions triggered_by: transaction do
        Contract.set_content List.size([])
      end
      """

      assert {%Transaction{data: %TransactionData{content: "0"}}, _state} =
               sanitize_parse_execute(code)
    end

    test "should work" do
      code = ~s"""
      actions triggered_by: transaction do
        list = ["Jennifer", "John", "Jean", "Julie"]
        Contract.set_content List.size(list)
      end
      """

      assert {%Transaction{data: %TransactionData{content: "4"}}, _state} =
               sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "in?/2" do
    test "should work" do
      code = ~s"""
      actions triggered_by: transaction do
        list = ["Jennifer", "John", "Jean", "Julie"]
        if List.in?(list, "Julie") do
          Contract.set_content "ok"
        else
          Contract.set_content "ko"
        end
      end
      """

      assert {%Transaction{data: %TransactionData{content: "ok"}}, _state} =
               sanitize_parse_execute(code)

      code = ~s"""
      actions triggered_by: transaction do
        list = ["Jennifer", "John", "Jean", "Julie"]
        if List.in?(list, "Julia") do
          Contract.set_content "ko"
        else
          Contract.set_content "ok"
        end
      end
      """

      assert {%Transaction{data: %TransactionData{content: "ok"}}, _state} =
               sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "empty?/1" do
    test "should work" do
      code = ~s"""
      actions triggered_by: transaction do
        list = []
        if List.empty?(list) do
          Contract.set_content "ok"
        else
          Contract.set_content "ko"
        end
      end
      """

      assert {%Transaction{data: %TransactionData{content: "ok"}}, _state} =
               sanitize_parse_execute(code)

      code = ~s"""
      actions triggered_by: transaction do
        list = ["Jennifer", "John", "Jean", "Julie"]
        if List.empty?(list) do
          Contract.set_content "ko"
        else
          Contract.set_content "ok"
        end
      end
      """

      assert {%Transaction{data: %TransactionData{content: "ok"}}, _state} =
               sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "concat/1" do
    test "should work" do
      code = ~s"""
      actions triggered_by: transaction do
        list = [1,2]
        if true do
          list = List.concat([list, [3,4]])
        end

        Contract.set_content Json.to_string(list)
      end
      """

      assert {%Transaction{data: %TransactionData{content: "[1,2,3,4]"}}, _state} =
               sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "append/2" do
    test "should work" do
      code = ~s"""
      actions triggered_by: transaction do
        list = [1,2]
        if true do
          list = List.append(list, 3)
        end

        Contract.set_content Json.to_string(list)
      end
      """

      assert {%Transaction{data: %TransactionData{content: "[1,2,3]"}}, _state} =
               sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "prepend/1" do
    test "should work" do
      code = ~s"""
      actions triggered_by: transaction do
        list = [1,2]
        if true do
          list = List.prepend(list, 0)
        end

        Contract.set_content Json.to_string(list)
      end
      """

      assert {%Transaction{data: %TransactionData{content: "[0,1,2]"}}, _state} =
               sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "join/2" do
    test "should work" do
      code = ~s"""
      actions triggered_by: transaction do
        list = ["Emma", "Joseph", "Emily"]
        Contract.set_content List.join(list, ", ")
      end
      """

      assert {%Transaction{data: %TransactionData{content: "Emma, Joseph, Emily"}}, _state} =
               sanitize_parse_execute(code)
    end
  end
end
