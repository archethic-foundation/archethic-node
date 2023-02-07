defmodule Archethic.Contracts.Interpreter.Version1.ActionInterpreterTest do
  use ArchethicCase

  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.Version1.ActionInterpreter

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  doctest ActionInterpreter

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

    test "should be able to use whitelisted module" do
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
  end

  describe "execute/2" do
    test "should be able to call the Contract module" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content "hello"
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

    # test "should evaluate actions based on if statement" do
    #   code = ~S"""
    #   actions triggered_by: transaction do
    #     if true do
    #       Contract.set_content "yes"
    #     else
    #       Contract.set_content "no"
    #     end
    #   end
    #   """

    #   assert %Transaction{data: %TransactionData{content: "yes"}} = sanitize_parse_execute(code)
    # end
  end

  defp sanitize_parse_execute(code, constants \\ %{}) do
    with {:ok, sanitized_code} <- Interpreter.sanitize_code(code),
         {:ok, _, action_ast} <- ActionInterpreter.parse(sanitized_code) do
      ActionInterpreter.execute(action_ast, constants)
    end
  end
end
