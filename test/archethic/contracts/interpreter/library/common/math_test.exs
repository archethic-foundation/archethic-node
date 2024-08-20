defmodule Archethic.Contracts.Interpreter.Library.Common.MathTest do
  use ArchethicCase

  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.Contracts.Interpreter.Library.Common.Math

  doctest Math

  test "exceed decimals raise" do
    assert_raise Library.Error, "Number exceeds decimals", fn ->
      Math.bigint(0.1234, 2)
    end

    assert_raise Library.Error, "Number exceeds decimals", fn ->
      Math.bigint(0.12345874564, 8)
    end
  end
end
