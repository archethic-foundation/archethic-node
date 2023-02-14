defmodule Archethic.Contracts.Interpreter.Version1.ActionInterpreterTest do
  use ArchethicCase

  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.Version1.ActionInterpreter

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  doctest ActionInterpreter

  # ----------------------------------------------
  # parse/1
  # ----------------------------------------------
  describe "parse/1" do
    test "should not be able to parse when there is a non-whitelisted module" do
      code = ~S"""
      actions triggered_by: transaction do
        String.to_atom "hello"
      end
      """

      assert {:error, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()
    end

    test "should be able to use whitelisted module existing function" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content "hello"
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()
    end

    test "should be able to have comments" do
      code = ~S"""
      actions triggered_by: transaction do
        # this is a comment
        "hello contract"
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()
    end

    test "should return the correct trigger type" do
      code = ~S"""
      actions triggered_by: oracle do
      end
      """

      assert {:ok, :oracle, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()

      code = ~S"""
      actions triggered_by: interval, at: "* * * * *"  do
      end
      """

      assert {:ok, {:interval, "* * * * *"}, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()

      code = ~S"""
      actions triggered_by: datetime, at: 1676282771 do
      end
      """

      assert {:ok, {:datetime, ~U[2023-02-13 10:06:11Z]}, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()
    end

    test "should not be able to use whitelisted module non existing function" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.non_existing_fn()
      end
      """

      assert {:error, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()

      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content("hello", "hola")
      end
      """

      assert {:error, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()
    end

    test "should be able to create variables" do
      code = ~S"""
      actions triggered_by: transaction do
        content = "hello"
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()
    end

    test "should be able to create lists" do
      code = ~S"""
      actions triggered_by: transaction do
        list = [1,2,3]
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()
    end

    test "should be able to create keywords" do
      code = ~S"""
      actions triggered_by: transaction do
        numbers = [one: 1, two: 2, three: 3]
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()
    end

    test "should be able to use common functions" do
      code = ~S"""
      actions triggered_by: transaction do
        numbers = [1,2,3]
        List.take_element_at_index(numbers, 1)
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()
    end

    test "should not be able to use non existing functions" do
      code = ~S"""
      actions triggered_by: transaction do
        numbers = [1,2,3]
        List.take_element_at_index(numbers, 1, 2, 3)
      end
      """

      assert {:error, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()

      code = ~S"""
      actions triggered_by: transaction do
        numbers = [1,2,3]
        List.non_existing_function()
      end
      """

      assert {:error, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()
    end

    test "should not be able to use wrong types in common functions" do
      code = ~S"""
      actions triggered_by: transaction do
        numbers = [1,2,3]
        List.take_element_at_index(1, numbers)
      end
      """

      assert {:error, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()
    end

    test "should be able to use the result of a function call as a parameter" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content Json.to_string([1,2,3])
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()
    end

    test "should not be able to use wrong types in contract functions" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content [1,2,3]
      end
      """

      assert {:error, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()
    end

    test "should not be able to use if as an expression" do
      code = ~S"""
      actions triggered_by: transaction do
        var = if true do
          "foo"
        else
          "bar"
        end
      end
      """

      assert {:error, _, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()
    end

    test "should be able to use nested ." do
      code = ~S"""
      actions triggered_by: transaction do
        numbers = [one: 1, two: 2, three: 3]
        var = [numbers: numbers]

        Contract.set_content var.numbers.one
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()

      code = ~S"""
      actions triggered_by: transaction do
        a = [b: [c: [d: [e: [f: [g: [h: "hello"]]]]]]]

        Contract.set_content a.b.c.d.e.f.g.h
      end
      """

      assert {:ok, :transaction, _} =
               code
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()
    end
  end

  # ----------------------------------------------
  # execute/2
  # ----------------------------------------------

  describe "execute/2" do
    test "should be able to call the Contract module" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content "hello"
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)
    end

    test "should be able to change the contract even if there are code after" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content "hello"
        some = "code"
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)
    end

    test "should be able to use a variable" do
      code = ~S"""
      actions triggered_by: transaction do
        content = "hello"
        Contract.set_content content
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)
    end

    test "should be able to use a function call as parameter" do
      code = ~S"""
      actions triggered_by: transaction do
        content = "hello"
        Contract.set_content Json.to_string(content)
      end
      """

      assert %Transaction{data: %TransactionData{content: "\"hello\""}} =
               sanitize_parse_execute(code)
    end

    test "should be able to use a keyword as a map" do
      code = ~S"""
      actions triggered_by: transaction do
        content = [text: "hello"]
        Contract.set_content content.text
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)
    end

    test "should be able to use a common module" do
      code = ~S"""
      actions triggered_by: transaction do
        content = [1,2,3]
        two = List.take_element_at_index(content, 1)
        Contract.set_content two
      end
      """

      assert %Transaction{data: %TransactionData{content: "2"}} = sanitize_parse_execute(code)
    end

    test "should evaluate actions based on if statement" do
      code = ~S"""
      actions triggered_by: transaction do
        if true do
          Contract.set_content "yes"
        else
          Contract.set_content "no"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "yes"}} = sanitize_parse_execute(code)
    end

    test "should consider the ! (not) keyword" do
      code = ~S"""
      actions triggered_by: transaction do
        if !false do
          Contract.set_content "yes"
        else
          Contract.set_content "no"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "yes"}} = sanitize_parse_execute(code)
    end

    test "should not parse if trying to access an undefined variable" do
      code = ~S"""
      actions triggered_by: transaction do
        if true do
          content = "hello"
        end
        Contract.set_content content
      end
      """

      # TODO: we want a parsing error not a runtime error
      assert_raise FunctionClauseError, fn ->
        sanitize_parse_execute(code)
      end
    end

    test "should be able to access a parent scope variable" do
      code = ~S"""
      actions triggered_by: transaction do
        content = "hello"
        if true do
          Contract.set_content content
        else
          Contract.set_content "should not happen"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        content = "hello"
        if true do
          if true do
            Contract.set_content content
          end
        else
          Contract.set_content "should not happen"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)
    end

    test "should be able to have variable in block" do
      code = ~S"""
      actions triggered_by: transaction do
        if true do
          content = "hello"
          Contract.set_content content
        else
          Contract.set_content "should not happen"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        if true do
          content = "hello"
          if true do
            Contract.set_content content
          end
        else
          Contract.set_content "should not happen"
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)
    end

    test "should be able to update a parent scope variable" do
      code = ~S"""
      actions triggered_by: transaction do
        content = ""

        if true do
          content = "hello"
        end

        Contract.set_content content
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        content = ""

        if false do
          content = "hello"
        end

        Contract.set_content content
      end
      """

      assert nil == sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        content = ""

        if false do
          content = "should not happen"
        else
          content = "hello"
        end

        Contract.set_content content
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        content = ""

        if true do
          content = "layer 1"
          if true do
            content = "layer 2"
            if true do
              content = "layer 3"
            end
          end
        end

        Contract.set_content content
      end
      """

      assert %Transaction{data: %TransactionData{content: "layer 3"}} =
               sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        content = ""

        if true do
          if true do
            if true do
              content = "layer 3"
            end
          end
        end

        Contract.set_content content
      end
      """

      assert %Transaction{data: %TransactionData{content: "layer 3"}} =
               sanitize_parse_execute(code)
    end

    test "should be able to use nested ." do
      code = ~S"""
      actions triggered_by: transaction do
        numbers = [one: 1, two: 2, three: 3]
        var = [numbers: numbers]

        Contract.set_content var.numbers.one
      end
      """

      assert %Transaction{data: %TransactionData{content: "1"}} = sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        a = [b: [c: [d: [e: [f: [g: [h: "hello"]]]]]]]

        Contract.set_content a.b.c.d.e.f.g.h
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do

        if true do
          a = [b: [c: [d: [e: [f: [g: [h: "hello"]]]]]]]
          if true do
            Contract.set_content a.b.c.d.e.f.g.h
          end
        end
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)
    end
  end

  defp sanitize_parse_execute(code, constants \\ %{}) do
    with {:ok, sanitized_code} <- Interpreter.sanitize_code(code),
         {:ok, _, action_ast} <- ActionInterpreter.parse(sanitized_code) do
      ActionInterpreter.execute(action_ast, constants)
    end
  end
end
