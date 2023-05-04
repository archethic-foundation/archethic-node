defmodule Archethic.Contracts.Interpreter.Library.Common.StringTest do
  @moduledoc """
  Here we test the module within the action block. Because there is AST modification (such as keywords to maps)
  in the ActionInterpreter and we want to test the whole thing.
  """

  use ArchethicCase
  import ArchethicCase

  alias Archethic.Contracts.Interpreter.Library.Common.String

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  doctest String

  # ----------------------------------------
  describe "size/1" do
    test "should work" do
      code = ~s"""
      actions triggered_by: transaction do
        Contract.set_content String.size("hello")
      end
      """

      assert %Transaction{data: %TransactionData{content: "5"}} = sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "in?/1" do
    test "should work" do
      code = ~s"""
      actions triggered_by: transaction do
        if String.in?("bob,alice", "bob") do
          Contract.set_content "ok"
        else
          Contract.set_content "ko"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)

      code = ~s"""
      actions triggered_by: transaction do
        if String.in?("bob,alice", "robert") do
          Contract.set_content "ko"
        else
          Contract.set_content "ok"

        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "to_number/1" do
    test "should parse integer" do
      code = ~s"""
      actions triggered_by: transaction do
        if String.to_number("14") == 14 do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end

    test "should parse float" do
      code = ~s"""
      actions triggered_by: transaction do
        if String.to_number("14.1") == 14.1 do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end

    test "should return nil if not a number" do
      code = ~s"""
      actions triggered_by: transaction do
        if String.to_number("bob") == nil do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "from_number/1" do
    test "should convert int" do
      code = ~s"""
      actions triggered_by: transaction do
        if String.from_number(14) == "14" do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end

    test "should convert float" do
      code = ~s"""
      actions triggered_by: transaction do
        if String.from_number(14.1) == "14.1" do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end

    test "should display float as int if possible" do
      code = ~s"""
      actions triggered_by: transaction do
        if String.from_number(14.0) == "14" do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end
  end
end
