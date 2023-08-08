defmodule Archethic.Contracts.Interpreter.ConditionInterpreterTest do
  use ArchethicCase

  alias Archethic.Contracts.ContractConditions, as: Conditions
  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.ConditionInterpreter

  doctest ConditionInterpreter

  describe "parse/1" do
    test "parse a condition inherit" do
      code = ~s"""
      condition inherit: [      ]
      """

      assert {:ok, :inherit, %Conditions{}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end

    test "parse a condition oracle" do
      code = ~s"""
      condition oracle: [      ]
      """

      assert {:ok, :oracle, %Conditions{}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end

    test "parse a condition transaction" do
      code = ~s"""
      condition transaction: [      ]
      """

      assert {:ok, :transaction, %Conditions{}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end

    test "does not parse anything else" do
      code = ~s"""
      condition foo: [      ]
      """

      assert {:error, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end
  end

  describe "parse/1 field" do
    test "should not parse an unknown field" do
      code = ~s"""
      condition inherit: [  foo: true    ]
      """

      assert {:error, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end

    test "parse strict value" do
      code = ~s"""
      condition transaction: [
        content: "Hello"
      ]
      """

      assert {:ok, :transaction, %Conditions{content: ast}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])

      assert is_tuple(ast) && :ok == Macro.validate(ast)
    end

    test "parse library functions" do
      code = ~s"""
      condition transaction: [
        uco_transfers: Map.size() > 0
      ]
      """

      assert {:ok, :transaction, %Conditions{uco_transfers: ast}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])

      assert is_tuple(ast) && :ok == Macro.validate(ast)
    end

    test "should not parse :write_contract functions" do
      code = ~s"""
      condition transaction: [
        uco_transfers: Contract.set_content "content"
      ]
      """

      assert {:error, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end

    test "parse custom functions" do
      code = ~s"""
      condition transaction: [
        uco_transfers: get_uco_transfers() > 0
      ]
      """

      assert {:ok, :transaction, %Conditions{uco_transfers: ast}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               # mark function as existing
               |> ConditionInterpreter.parse([{"get_uco_transfers", 0, :public}])

      assert is_tuple(ast) && :ok == Macro.validate(ast)
    end

    test "parse true" do
      code = ~s"""
      condition transaction: [
        content: true
      ]
      """

      assert {:ok, :transaction, %Conditions{content: true}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end

    test "parse false" do
      code = ~s"""
      condition transaction: [
        content: false
      ]
      """

      assert {:ok, :transaction, %Conditions{content: false}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end

    test "parse AST" do
      code = ~s"""
      condition transaction: [
        content: if true do "Hello" else "World" end
      ]
      """

      assert {:ok, :transaction, %Conditions{content: {:__block__, _, _}}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end

    test "parse named action 0 arg" do
      code = ~s"""
      condition transaction, on: upgrade, as: []
      """

      assert {:ok, {:transaction, "upgrade", 0}, %Conditions{}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end

    test "parse named action 1 arg" do
      code = ~s"""
      condition transaction, on: vote(candidate), as: []
      """

      assert {:ok, {:transaction, "vote", 1}, %Conditions{}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end

    test "parse named action n args" do
      code = ~s"""
      condition transaction, on: count(x, y), as: []
      """

      assert {:ok, {:transaction, "count", 2}, %Conditions{}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end
  end
end
