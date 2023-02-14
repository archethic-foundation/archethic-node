defmodule Archethic.Contracts.Interpreter.Version1.Library.Common.MapTest do
  @moduledoc """
  Here we test the module within the action block. Because there is AST modification (such as keywords to maps)
  in the ActionInterpreter and we want to test the whole thing.
  """

  use ArchethicCase

  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.Version1.ActionInterpreter
  alias Archethic.Contracts.Interpreter.Version1.Library.Common.Map

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  doctest Map

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

  defp sanitize_parse_execute(code, constants \\ %{}) do
    with {:ok, sanitized_code} <- Interpreter.sanitize_code(code),
         {:ok, _, action_ast} <- ActionInterpreter.parse(sanitized_code) do
      ActionInterpreter.execute(action_ast, constants)
    end
  end
end
