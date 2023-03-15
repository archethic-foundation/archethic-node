defmodule Archethic.Contracts.InterpreterTest do
  @moduledoc false
  use ArchethicCase

  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Interpreter
  alias Archethic.ContractFactory

  doctest Interpreter

  describe "strict versionning" do
    test "should return ok if version exists" do
      assert {:ok, _} = Interpreter.parse(ContractFactory.valid_version1_contract())
      assert {:ok, _} = Interpreter.parse(ContractFactory.valid_legacy_contract())
    end

    test "should return an error if version does not exist yet" do
      code_v0 = ~s"""
      @version 20
      #{ContractFactory.valid_legacy_contract()}
      """

      code_v1 = ~s"""
      @version 20
      #{ContractFactory.valid_version1_contract(version_attribute: false)}
      """

      assert {:error, "@version not supported"} = Interpreter.parse(code_v0)
      assert {:error, "@version not supported"} = Interpreter.parse(code_v1)
    end

    test "should return an error if version is invalid" do
      code_v0 = ~s"""
      @version 1.5
      #{ContractFactory.valid_legacy_contract()}
      """

      assert {:error, "@version not supported"} = Interpreter.parse(code_v0)
    end
  end

  describe "parse code v1" do
    test "should return an error if there are unexpected terms" do
      assert {:error, _} =
               """
               @version 1
               condition transaction: [
                uco_transfers: List.size() > 0
               ]

               some_unexpected_code

               actions triggered_by: transaction do
                Contract.set_content "hello"
               end
               """
               |> Interpreter.parse()
    end

    test "should return the contract if format is OK" do
      assert {:ok, %Contract{}} =
               """
               @version 1
               condition transaction: [
                uco_transfers: List.size() > 0
               ]

               actions triggered_by: transaction do
                Contract.set_content "hello"
               end
               """
               |> Interpreter.parse()
    end
  end

  describe "parse code v0" do
    test "should return an error if there are unexpected terms" do
      assert {:error, _} =
               """
               condition transaction: [
                uco_transfers: size() > 0
               ]

               some_unexpected_code

               actions triggered_by: transaction do
                set_content "hello"
               end
               """
               |> Interpreter.parse()
    end

    test "should return the contract if format is OK" do
      assert {:ok, %Contract{}} =
               """
               condition transaction: [
                uco_transfers: size() > 0
               ]

               actions triggered_by: transaction do
                set_content "hello"
               end
               """
               |> Interpreter.parse()
    end
  end
end
