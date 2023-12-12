defmodule Archethic.Contracts.Interpreter.ConditionInterpreterTest do
  use ArchethicCase

  alias Archethic.Contracts.Conditions.Subjects, as: ConditionsSubjects
  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.ConditionInterpreter
  alias Archethic.Contracts.Interpreter.FunctionKeys

  doctest ConditionInterpreter

  describe "parse/1" do
    test "parse a condition inherit" do
      code = ~s"""
      condition inherit: [      ]
      """

      assert {:ok, :inherit, %ConditionsSubjects{}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end

    test "parse a condition oracle" do
      code = ~s"""
      condition oracle: [      ]
      """

      assert {:ok, :oracle, %ConditionsSubjects{}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])

      code = ~s"""
      condition triggered_by: oracle, as: [      ]
      """

      assert {:ok, :oracle, %ConditionsSubjects{}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end

    test "parse a condition transaction" do
      code = ~s"""
      condition transaction: [      ]
      """

      assert {:ok, {:transaction, nil, nil}, %ConditionsSubjects{}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])

      code = ~s"""
      condition triggered_by: transaction, as: [      ]
      """

      assert {:ok, {:transaction, nil, nil}, %ConditionsSubjects{}} =
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

      code = ~s"""
      condition triggered_by: foo, as: [      ]
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
      condition triggered_by: transaction, as: [
        content: "Hello"
      ]
      """

      assert {:ok, {:transaction, nil, nil}, %ConditionsSubjects{content: ast}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])

      assert is_tuple(ast) && :ok == Macro.validate(ast)
    end

    test "parse library functions" do
      code = ~s"""
      condition triggered_by: transaction, as: [
        uco_transfers: Map.size() > 0
      ]
      """

      assert {:ok, {:transaction, nil, nil}, %ConditionsSubjects{uco_transfers: ast}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])

      assert is_tuple(ast) && :ok == Macro.validate(ast)
    end

    test "should not parse :write_contract functions" do
      code = ~s"""
       condition triggered_by: transaction, as: [
        uco_transfers: Contract.set_content "content"
      ]
      """

      assert {:error, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end

    test "should not parse :write_state functions" do
      code = ~s"""
       condition triggered_by: transaction, as: [
        uco_transfers: State.set("foo", "bar")
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
       condition triggered_by: transaction, as: [
        uco_transfers: get_uco_transfers() > 0
      ]
      """

      assert {:ok, {:transaction, nil, nil}, %ConditionsSubjects{uco_transfers: ast}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               # mark function as existing
               |> ConditionInterpreter.parse(
                 FunctionKeys.new()
                 |> FunctionKeys.add_public("get_uco_transfers", 0)
               )

      assert is_tuple(ast) && :ok == Macro.validate(ast)
    end

    test "parse true" do
      code = ~s"""
       condition triggered_by: transaction, as: [
        content: true
      ]
      """

      assert {:ok, {:transaction, nil, nil}, %ConditionsSubjects{content: true}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end

    test "parse false" do
      code = ~s"""
       condition triggered_by: transaction, as: [
        content: false
      ]
      """

      assert {:ok, {:transaction, nil, nil}, %ConditionsSubjects{content: false}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end

    test "parse AST" do
      code = ~s"""
       condition triggered_by: transaction, as: [
        content: if true do "Hello" else "World" end
      ]
      """

      assert {:ok, {:transaction, nil, nil}, %ConditionsSubjects{content: {:__block__, _, _}}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end

    test "parse named action 0 arg" do
      code = ~s"""
      condition triggered_by: transaction, on: upgrade, as: []
      """

      assert {:ok, {:transaction, "upgrade", []}, %ConditionsSubjects{}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end

    test "parse named action 1 arg" do
      code = ~s"""
      condition triggered_by: transaction, on: vote(candidate), as: []
      """

      assert {:ok, {:transaction, "vote", ["candidate"]}, %ConditionsSubjects{}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end

    test "parse named action n args" do
      code = ~s"""
      condition triggered_by: transaction, on: count(x, y), as: []
      """

      assert {:ok, {:transaction, "count", ["x", "y"]}, %ConditionsSubjects{}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end

    test "should not parse action > 255 byte" do
      code = ~s"""
      condition triggered_by: transaction, on: abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuv(x, y), as: []
      """

      assert {:error, {_, "atom length must be less" <> _, _}} =
               code
               |> Interpreter.sanitize_code()
    end
  end

  describe "do-end syntax" do
    test "should parse a unnamed action" do
      code = ~s"""
      condition triggered_by: transaction do
        true
      end
      """

      assert {:ok, {:transaction, nil, nil}, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end

    test "should parse a named action" do
      code = ~s"""
      condition triggered_by: transaction, on: count(x, y) do
        true
      end
      """

      assert {:ok, {:transaction, "count", ["x", "y"]}, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end

    test "should parse a library function" do
      code = ~s"""
      condition triggered_by: transaction do
        String.size("hello") == 5
      end
      """

      assert {:ok, {:transaction, nil, nil}, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end

    test "should not parse if library function arity is not good" do
      code = ~s"""
      condition triggered_by: transaction do
        String.size() == 5
      end
      """

      assert {:error, _, "Function String.size does not exists with 0 arguments"} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse([])
    end

    test "should parse a custom function" do
      code = ~s"""
      condition triggered_by: transaction do
        myfun("hello") == 5
      end
      """

      assert {:ok, {:transaction, nil, nil}, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse(%{
                 {"myfun", 1} => :private
               })
    end

    test "should not parse if function arity is not good" do
      code = ~s"""
      condition triggered_by: transaction do
        myfun() == 5
      end
      """

      assert {:error, _, "The function myfun/0 does not exist"} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse(%{
                 {"myfun", 1} => :private
               })
    end
  end
end
