defmodule Archethic.Contracts.Interpreter.Library.Common.StringTest do
  @moduledoc """
  Here we test the module within the action block. Because there is AST modification (such as keywords to maps)
  in the ActionInterpreter and we want to test the whole thing.
  """

  use ArchethicCase

  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.ActionInterpreter
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
  describe "to_int/1" do
    test "should work" do
      code = ~s"""
      actions triggered_by: transaction do
        if String.to_int("14") == 14 do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "from_int/1" do
    test "should work" do
      code = ~s"""
      actions triggered_by: transaction do
        if String.from_int(14) == "14" do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "to_float/1" do
    test "should work" do
      code = ~s"""
      actions triggered_by: transaction do
        if String.to_float("0.1") == 0.1 do
          Contract.set_content "ok"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "from_float/1" do
    test "should work" do
      code = ~s"""
      actions triggered_by: transaction do
        if String.from_float(0.1) == "0.1" do
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
