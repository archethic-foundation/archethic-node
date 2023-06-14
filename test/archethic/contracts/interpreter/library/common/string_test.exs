defmodule Archethic.Contracts.Interpreter.Library.Common.StringTest do
  @moduledoc """
  Here we test the module within the action block. Because there is AST modification (such as keywords to maps)
  in the ActionInterpreter and we want to test the whole thing.
  """

  use ArchethicCase
  import ArchethicCase

  alias Archethic.Contracts.Interpreter.Library.Common.String
  alias Archethic.Contracts.ContractConstants, as: Constants

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

  # ----------------------------------------
  describe "to_hex/1" do
    test "should work on a string" do
      code = ~s"""
      actions triggered_by: transaction do
          Contract.set_content String.to_hex("abc123def456")
      end
      """

      assert %Transaction{data: %TransactionData{content: "ABC123DEF456"}} =
               sanitize_parse_execute(code)
    end

    test "should work on a variable" do
      code = ~s"""
      actions triggered_by: transaction do
          var = "abc123def456"
          Contract.set_content String.to_hex(var)
      end
      """

      assert %Transaction{data: %TransactionData{content: "ABC123DEF456"}} =
               sanitize_parse_execute(code)
    end

    test "should work on a constant" do
      code = ~s"""
      actions triggered_by: transaction do
          Contract.set_content String.to_hex(transaction.address)
      end
      """

      address = random_address()

      trigger_tx = %Transaction{
        type: :data,
        address: address,
        data: %TransactionData{}
      }

      assert %Transaction{data: %TransactionData{content: hex}} =
               sanitize_parse_execute(code, %{
                 "transaction" => Constants.from_transaction(trigger_tx)
               })

      assert address == Base.decode16!(hex)
    end

    test "should be able to compare with hash" do
      code = ~s"""
      actions triggered_by: transaction do
          if Crypto.hash("foo") == String.to_hex("2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae") do
            Contract.set_content "ok"
          end
      end
      """

      assert %Transaction{data: %TransactionData{content: "ok"}} = sanitize_parse_execute(code)
    end

    test "should be able to compare" do
      address = random_address()

      code = ~s"""
      actions triggered_by: transaction do
          if transaction.address == String.to_hex("#{Base.encode16(address, case: :lower)}") do
            Contract.set_content "ok"
          end
      end
      """

      trigger_tx = %Transaction{
        type: :data,
        address: address,
        data: %TransactionData{}
      }

      assert %Transaction{data: %TransactionData{content: "ok"}} =
               sanitize_parse_execute(code, %{
                 "transaction" => Constants.from_transaction(trigger_tx)
               })
    end

    test "should not parse if compiler knows there is a type error" do
      code = ~s"""
      actions triggered_by: transaction do
          Contract.set_content String.to_hex(123)
      end
      """

      {:error, _, "invalid function arguments"} = sanitize_parse_execute(code)
    end

    test "should raise when not a hex" do
      # string with non-hex characters
      code = ~s"""
      actions triggered_by: transaction do
          Contract.set_content String.to_hex("zzz")
      end
      """

      assert_raise(ArgumentError, fn ->
        sanitize_parse_execute(code)
      end)

      # variable
      code = ~s"""
      actions triggered_by: transaction do
          var = "ZZZ"
          Contract.set_content String.to_hex(var)
      end
      """

      assert_raise(ArgumentError, fn ->
        sanitize_parse_execute(code)
      end)

      # string with invalid size
      code = ~s"""
      actions triggered_by: transaction do
          Contract.set_content String.to_hex("abc")
      end
      """

      assert_raise(ArgumentError, fn ->
        sanitize_parse_execute(code)
      end)
    end
  end

  # ----------------------------------------
  describe "to_uppercase/1" do
    test "should work on a string" do
      code = ~s"""
      actions triggered_by: transaction do
          Contract.set_content String.to_uppercase("IiIiIiIiIiII")
      end
      """

      assert %Transaction{data: %TransactionData{content: "IIIIIIIIIIII"}} =
               sanitize_parse_execute(code)
    end

    test "should work on a variable" do
      code = ~s"""
      actions triggered_by: transaction do
          var = "IiIiIiIiIiII"
          Contract.set_content String.to_uppercase(var)
      end
      """

      assert %Transaction{data: %TransactionData{content: "IIIIIIIIIIII"}} =
               sanitize_parse_execute(code)
    end

    test "should not parse if compiler knows there is a type error" do
      code = ~s"""
      actions triggered_by: transaction do
          Contract.set_content String.to_uppercase(123)
      end
      """

      {:error, _, "invalid function arguments"} = sanitize_parse_execute(code)
    end

    test "should raise when not a string" do
      code = ~s"""
      actions triggered_by: transaction do
          var = 123
          Contract.set_content String.to_uppercase(var)
      end
      """

      assert_raise(FunctionClauseError, fn ->
        sanitize_parse_execute(code)
      end)
    end
  end

  # ----------------------------------------
  describe "to_lowercase/1" do
    test "should work on a string" do
      code = ~s"""
      actions triggered_by: transaction do
          Contract.set_content String.to_lowercase("IiIiIiIiIiII")
      end
      """

      assert %Transaction{data: %TransactionData{content: "iiiiiiiiiiii"}} =
               sanitize_parse_execute(code)
    end

    test "should work on a variable" do
      code = ~s"""
      actions triggered_by: transaction do
          var = "IiIiIiIiIiII"
          Contract.set_content String.to_lowercase(var)
      end
      """

      assert %Transaction{data: %TransactionData{content: "iiiiiiiiiiii"}} =
               sanitize_parse_execute(code)
    end

    test "should not parse if compiler knows there is a type error" do
      code = ~s"""
      actions triggered_by: transaction do
          Contract.set_content String.to_lowercase(123)
      end
      """

      {:error, _, "invalid function arguments"} = sanitize_parse_execute(code)
    end

    test "should raise when not a string" do
      code = ~s"""
      actions triggered_by: transaction do
          var = 123
          Contract.set_content String.to_lowercase(var)
      end
      """

      assert_raise(FunctionClauseError, fn ->
        sanitize_parse_execute(code)
      end)
    end
  end
end
