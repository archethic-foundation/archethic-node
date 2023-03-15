defmodule Archethic.Contracts.Interpreter.ConditionInterpreterTest do
  use ArchethicCase

  alias Archethic.Contracts.ContractConditions, as: Conditions
  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.ConditionInterpreter
  alias Archethic.Contracts.Interpreter.ConditionValidator

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
        uco_transfers: Map.size() > 0
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

      assert {:ok, :transaction, %Conditions{content: {:__block__, _, _}}} =
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
             |> ConditionValidator.valid_conditions?(%{
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
             |> ConditionValidator.valid_conditions?(%{
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
             |> ConditionValidator.valid_conditions?(%{
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
             |> ConditionValidator.valid_conditions?(%{
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
             |> ConditionValidator.valid_conditions?(%{
               "next" => %{
                 "content" => "Hello"
               }
             })
    end

    test "should be able to use boolean expression in inherit" do
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
             |> ConditionValidator.valid_conditions?(%{
               "next" => %{
                 "uco_transfers" => %{"@addr" => 265_821}
               }
             })

      code = ~s"""
      condition inherit: [
        uco_transfers: Map.size() == 3
      ]
      """

      refute code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "next" => %{
                 "uco_transfers" => %{}
               }
             })
    end

    test "should be able to use boolean expression in transaction" do
      code = ~s"""
      condition transaction: [
        uco_transfers: Map.size() > 0
      ]
      """

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "transaction" => %{
                 "uco_transfers" => %{"@addr" => 265_821}
               }
             })

      code = ~s"""
      condition transaction: [
        uco_transfers: Map.size() == 1
      ]
      """

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "transaction" => %{
                 "uco_transfers" => %{"@addr" => 265_821}
               }
             })

      code = ~s"""
      condition transaction: [
        uco_transfers: Map.size() == 2
      ]
      """

      refute code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "transaction" => %{
                 "uco_transfers" => %{}
               }
             })

      code = ~s"""
      condition transaction: [
        uco_transfers: Map.size() < 10
      ]
      """

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "transaction" => %{
                 "uco_transfers" => %{"@addr" => 265_821}
               }
             })
    end

    test "should be able to use dot access" do
      code = ~s"""
      condition inherit: [
          content: previous.content == next.content
      ]
      """

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "previous" => %{"content" => "zoubida"},
               "next" => %{"content" => "zoubida"}
             })

      code = ~s"""
      condition inherit: [
        content: previous.content == next.content
      ]
      """

      refute code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "previous" => %{"content" => "lavabo"},
               "next" => %{"content" => "bidet"}
             })
    end

    test "should be able to use nested dot access" do
      code = ~s"""
      condition inherit: [
        content: previous.content.y == "foobar"
      ]
      """

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "previous" => %{"content" => %{"y" => "foobar"}},
               "next" => %{}
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
             |> ConditionValidator.valid_conditions?(%{
               "previous" => %{},
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
             |> ConditionValidator.valid_conditions?(%{
               "previous" => %{},
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
             |> ConditionValidator.valid_conditions?(%{
               "previous" => %{},
               "next" => %{
                 "content" => "Hello"
               }
             })
    end

    test "should be able to use variables in the AST" do
      code = ~s"""
      condition inherit: [
        content: (
          x = 1
          if true do
            x == 1
          end
        )
      ]
      """

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "previous" => %{},
               "next" => %{}
             })
    end

    test "should be able to use for loops" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      condition inherit: [
        uco_transfers: (
          found = false

          # search for a transfer of 1 uco to address
          for address in Map.keys(next.uco_transfers) do
            if address == "#{Base.encode16(address)}" && next.uco_transfers[address] == 1 do
              found = true
            end
          end

          found
        )
      ]
      """

      assert code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ConditionInterpreter.parse()
             |> elem(2)
             |> ConditionValidator.valid_conditions?(%{
               "previous" => %{},
               "next" => %{
                 "uco_transfers" => %{
                   address => 1
                 }
               }
             })
    end
  end
end
