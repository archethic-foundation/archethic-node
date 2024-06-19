defmodule Archethic.Contracts.Interpreter.Library.Common.StringTest do
  @moduledoc """
  Here we test the module within the action block. Because there is AST modification (such as keywords to maps)
  in the ActionInterpreter and we want to test the whole thing.
  """

  use ArchethicCase

  alias Archethic.Contracts.Interpreter.Library.Common.String

  doctest String

  # ----------------------------------------
  describe "size/1" do
    test "should return the size of a string" do
      assert String.size("hello") == 5
    end
  end

  # ----------------------------------------
  describe "in?/1" do
    test "should return true if a string contains another string" do
      assert String.in?("bob,alice", "bob")
    end

    test "shoudl return false if a string does not contain another string" do
      refute String.in?("bob,alice", "robert")
    end
  end

  # ----------------------------------------
  describe "to_number/1" do
    test "should parse integer" do
      assert 14 == String.to_number("14")
    end

    test "should parse float" do
      assert String.to_number("14.1") == Decimal.new("14.1")
    end

    test "should return nil if not a number" do
      assert String.to_number("bob") == nil
    end
  end

  # ----------------------------------------
  describe "from_number/1" do
    test "should convert int" do
      assert String.from_number(14) == "14"
      assert Decimal.new("14") |> String.from_number() == "14"
    end

    test "should convert float" do
      assert Decimal.new("14.1") |> String.from_number() == "14.1"
    end

    test "should display float as int if possible" do
      assert Decimal.new("14.0") |> String.from_number() == "14"
    end
  end

  # ----------------------------------------
  describe "to_hex/1" do
    test "should convert string to hex" do
      assert "77696C6C206265636F6D6520686578" == String.to_hex("will become hex")
    end

    test "should keep hex if string is already hex" do
      assert "ABCD" = String.to_hex("ABCD")
      assert "ABCD" = String.to_hex("abcd")
    end
  end

  # ----------------------------------------
  describe "to_uppercase/1" do
    test "should convert string to uppercase" do
      assert String.to_uppercase("IiIiIiIiIiII") == "IIIIIIIIIIII"
    end
  end

  # ----------------------------------------
  describe "to_lowercase/1" do
    test "should convert string to lowercase" do
      assert String.to_lowercase("IiIiIiIiIiII") == "iiiiiiiiiiii"
    end
  end
end
