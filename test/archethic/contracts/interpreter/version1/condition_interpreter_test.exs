defmodule Archethic.Contracts.Interpreter.Version1.ConditionInterpreterTest do
  use ArchethicCase

  alias Archethic.Contracts.ContractConditions, as: Conditions
  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.Version1.ConditionInterpreter

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

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
               |> ConditionInterpreter.parse()
    end

    test "parse a condition oracle" do
      code = ~s"""
      condition oracle: [      ]
      """

      assert {:ok, :oracle, %Conditions{}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse()
    end

    test "parse a condition transaction" do
      code = ~s"""
      condition transaction: [      ]
      """

      assert {:ok, :transaction, %Conditions{}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse()
    end

    test "does not parse anything else" do
      code = ~s"""
      condition foo: [      ]
      """

      assert {:error, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse()
    end
  end

  describe "parse/1 field" do
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
               |> ConditionInterpreter.parse()

      assert is_tuple(ast) && :ok == Macro.validate(ast)
    end

    test "parse library functions" do
      code = ~s"""
      condition transaction: [
        uco_transfers: List.size() > 0
      ]
      """

      assert {:ok, :transaction, %Conditions{uco_transfers: ast}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse()

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
               |> ConditionInterpreter.parse()
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
               |> ConditionInterpreter.parse()
    end

    test "parse AST" do
      code = ~s"""
      condition transaction: [
        content: if true do "Hello" else "World" end
      ]
      """

      assert {:ok, :transaction, %Conditions{content: {:if, _, _}}} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ConditionInterpreter.parse()
    end
  end

  describe "valid_conditions?/2" do
    test "should return true if the transaction's conditions are valid" do
      code = ~s"""
      condition transaction: [
        type: "transfer"
      ]
      """

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
             |> elem(2)
             |> ConditionInterpreter.valid_conditions?(%{
               "transaction" => %{
                 "type" => "transfer"
               }
             })
    end

    test "should return true if the inherit's conditions are valid" do
      code = ~s"""
      condition inherit: [
        content: "Hello"
      ]
      """

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
             |> elem(2)
             |> ConditionInterpreter.valid_conditions?(%{
               "next" => %{
                 "content" => "Hello"
               }
             })
    end

    test "should return true if the oracle's conditions are valid" do
      code = ~s"""
      condition oracle: [
        content: "Hello"
      ]
      """

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
             |> elem(2)
             |> ConditionInterpreter.valid_conditions?(%{
               "transaction" => %{
                 "content" => "Hello"
               }
             })
    end

    test "should return true with a flexible condition" do
      code = ~s"""
      condition inherit: [
        content: true
      ]
      """

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
             |> elem(2)
             |> ConditionInterpreter.valid_conditions?(%{
               "next" => %{
                 "content" => "Hello"
               }
             })
    end

    test "should return false if modifying a value not in the condition" do
      code = ~s"""
      condition inherit: []
      """

      refute code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
             |> elem(2)
             |> ConditionInterpreter.valid_conditions?(%{
               "next" => %{
                 "content" => "Hello"
               }
             })
    end

    test "should be able to use boolean expression" do
      code = ~s"""
      condition inherit: [
        uco_transfers: Map.size() == 1
      ]
      """

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
             |> elem(2)
             |> ConditionInterpreter.valid_conditions?(%{
               "next" => %{
                 "uco_transfers" => %{"@addr" => 265_821}
               }
             })
    end

    test "should evaluate AST" do
      code = ~s"""
      condition inherit: [
        content: if true do "Hello" else "World" end
      ]
      """

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
             |> elem(2)
             |> ConditionInterpreter.valid_conditions?(%{
               "next" => %{
                 "content" => "Hello"
               }
             })

      code = ~s"""
      condition inherit: [
        content: if false do "Hello" else "World" end
      ]
      """

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
             |> elem(2)
             |> ConditionInterpreter.valid_conditions?(%{
               "next" => %{
                 "content" => "World"
               }
             })

      code = ~s"""
      condition inherit: [
        content: if false do "Hello" else "World" end
      ]
      """

      refute code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
             |> elem(2)
             |> ConditionInterpreter.valid_conditions?(%{
               "next" => %{
                 "content" => "Hello"
               }
             })
    end
  end
end
