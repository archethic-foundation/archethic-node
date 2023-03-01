defmodule Archethic.Contracts.InterpreterTest do
  @moduledoc false
  use ArchethicCase

  alias Archethic.Contracts.Interpreter
  alias Archethic.ContractFactory

  doctest Interpreter

  describe "strict versionning" do
    test "should return ok if version exists" do
      assert {:ok, _} = Interpreter.parse(ContractFactory.valid_version1_contract())
      assert {:ok, _} = Interpreter.parse(ContractFactory.valid_version0_contract())
    end

    test "should return an error if version does not exist yet" do
      code_v0 = ~s"""
      @version 20
      #{ContractFactory.valid_version0_contract()}
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
      #{ContractFactory.valid_version0_contract()}
      """

      assert {:error, "@version not supported"} = Interpreter.parse(code_v0)
    end
  end

  describe "version/1" do
    test "should return 0 if there is no interpreter tag" do
      code = ~s(some code)
      assert {0, ^code} = Interpreter.version(code)
    end

    test "should return the correct version if specified" do
      assert {0, "my_code"} = Interpreter.version(~s(@version 0\nmy_code))
      assert {1, "my_code"} = Interpreter.version(~s(@version 1\nmy_code))
    end

    test "should work even if there are some whitespaces" do
      assert {0, _} = Interpreter.version(~s(\n   \n   @version 0 \n  \n))
      assert {1, _} = Interpreter.version(~s(\n   \n   @version 1 \n  \n))
    end

    test "should return error if version is not formatted as expected" do
      assert :error = Interpreter.version(~s(@version "0"))
      assert :error = Interpreter.version(~s(@version "1"))
      assert :error = Interpreter.version(~s(@version 1.1))
      assert :error = Interpreter.version(~s(@version "1.1"))
      assert :error = Interpreter.version(~s(@version "1.1.1"))
    end
  end
end
