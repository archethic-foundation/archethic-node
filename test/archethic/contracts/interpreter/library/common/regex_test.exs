defmodule Archethic.Contracts.Interpreter.Library.Common.RegexTest do
  @moduledoc """
  Here we test the module within the action block. Because there is AST modification (such as keywords to maps)
  in the ActionInterpreter and we want to test the whole thing.
  """

  use ArchethicCase

  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.ActionInterpreter
  alias Archethic.Contracts.Interpreter.Library.Common.Regex

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  doctest Regex

  # ----------------------------------------
  describe "match?/2" do
    test "should match" do
      code = ~s"""
      actions triggered_by: transaction do
        if Regex.match?("lorem ipsum", "lorem") do
          Contract.set_content "match"
        else
          Contract.set_content "no match"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "match"}} = sanitize_parse_execute(code)
    end

    test "should not match" do
      code = ~s"""
      actions triggered_by: transaction do
        if Regex.match?("lorem ipsum", "LOREM") do
          Contract.set_content "match"
        else
          Contract.set_content "no match"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "no match"}} =
               sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "extract/2" do
    test "should extract" do
      code = ~s"""
      actions triggered_by: transaction do
        # doubled escape chars because it's in a string
        Contract.set_content Regex.extract("Michael,12", "\\\\d+")
      end
      """

      assert %Transaction{data: %TransactionData{content: "12"}} = sanitize_parse_execute(code)
    end

    test "should return empty when no match" do
      code = ~s"""
      actions triggered_by: transaction do
        x = Regex.extract("Michael,twelve", "\\\\d+")
        if x == "" do
          # FIXME: I can't do set_content("") apparently
          Contract.set_content "no match"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "no match"}} =
               sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "scan/2" do
    test "should work with single capture group" do
      code = ~s"""
      actions triggered_by: transaction do
        # doubled escape chars because it's in a string
        Contract.set_content Json.to_string(Regex.scan("Michael,12", "(\\\\d+)"))
      end
      """

      assert %Transaction{data: %TransactionData{content: "[\"12\"]"}} =
               sanitize_parse_execute(code)
    end

    test "should work with multiple capture group" do
      code = ~s"""
      actions triggered_by: transaction do
        # doubled escape chars because it's in a string
        Contract.set_content Json.to_string(Regex.scan("Michael,12", "(\\\\w+),(\\\\d+)"))
      end
      """

      assert %Transaction{data: %TransactionData{content: "[[\"Michael\",\"12\"]]"}} =
               sanitize_parse_execute(code)
    end
  end

  defp sanitize_parse_execute(code, constants \\ %{}) do
    with {:ok, sanitized_code} <- Interpreter.sanitize_code(code),
         {:ok, _, action_ast} <- ActionInterpreter.parse(sanitized_code) do
      ActionInterpreter.execute(action_ast, constants)
    end
  end
end
