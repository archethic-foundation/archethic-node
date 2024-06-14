defmodule Archethic.Contracts.Interpreter.Library.Common.Math do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Tag
  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST

  use Tag
  import Bitwise

  @one Decimal.new(1)

  @spec trunc(num :: integer() | Decimal.t()) :: integer()
  def trunc(num) when is_integer(num), do: num
  def trunc(num = %Decimal{}), do: Decimal.round(num) |> Decimal.to_integer()

  @doc """
  ##  Example
    iex> Math.pow(2, 3)
    8

    iex> Math.pow(-2, 3)
    -8

    iex> Math.pow(2, -3)
    0.125

    iex> Math.pow(1.7, 8)
    69.75757441

    iex> Math.pow(2, 0)
    1

    iex> Math.pow(6, 1)
    6
  """
  @spec pow(num :: number(), exp :: number()) :: number()
  def pow(num, 0) when is_number(num), do: 1
  def pow(num, 1) when is_number(num), do: num

  def pow(num, exp) when is_number(num) and is_integer(exp) and exp > 1 do
    dec_num = to_decimal(num)
    res = pow(@one, dec_num, exp)

    to_number(res, is_integer(num))
  end

  def pow(num, exp) when is_number(num) and is_integer(exp) and exp < 0 do
    dec_num = to_decimal(num)
    res = Decimal.div(@one, pow(@one, dec_num, -exp))

    to_number(res, is_integer(num))
  end

  defp pow(result, num, exp) when exp < 2 do
    Decimal.mult(result, num)
  end

  defp pow(result, num, exp) when (exp &&& 1) == 0 do
    pow(result, Decimal.mult(num, num), exp >>> 1)
  end

  defp pow(result, num, exp) when (exp &&& 1) == 1 do
    pow(Decimal.mult(result, num), Decimal.mult(num, num), exp >>> 1)
  end

  @doc """
  ## Examples
    iex> Math.sqrt(0)
    0

    iex> Math.sqrt(-0)
    -0

    iex> Math.sqrt(0.39)
    0.62449979

    iex> Math.sqrt(100)
    10

    iex> Math.sqrt(1)
    1

    iex> Math.sqrt(1.0)
    1.0

    iex> Math.sqrt(1.00)
    1.0

    iex> Math.sqrt(7)
    2.64575131
  """
  @spec sqrt(num :: number()) :: number()
  def sqrt(num) when is_number(num) do
    res = to_decimal(num) |> Decimal.sqrt()

    to_number(res, is_integer(num))
  end

  @doc """
  ## Example
    iex> Math.rem(2.1, 3)
    2.1

    iex> Math.rem(10, 3)
    1

    iex> Math.rem(-10, 3)
    -1

    iex> Math.rem(10.2, 1)
    0.2

    iex> Math.rem(10, 0.3)
    0.1

    iex> Math.rem(3.6, 1.3)
    1.0
  """
  @spec rem(num1 :: number(), num2 :: number()) :: number()
  def rem(num1, num2) when is_number(num1) and is_number(num2) do
    dec_num1 = to_decimal(num1)
    dec_num2 = to_decimal(num2)

    res = Decimal.rem(dec_num1, dec_num2)

    to_number(res, is_integer(num1) and is_integer(num2))
  end

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:trunc, [first]) do
    AST.is_number?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:sqrt, [first]) do
    AST.is_number?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:pow, [first, second]) do
    (AST.is_number?(first) || AST.is_variable_or_function_call?(first)) &&
      (AST.is_number?(second) || AST.is_variable_or_function_call?(second))
  end

  def check_types(:rem, [first, second]) do
    (AST.is_number?(first) || AST.is_variable_or_function_call?(first)) &&
      (AST.is_number?(second) || AST.is_variable_or_function_call?(second))
  end

  def check_types(_, _), do: false

  defp to_decimal(num) when is_integer(num), do: Decimal.new(num)
  defp to_decimal(num) when is_float(num), do: Decimal.from_float(num)

  defp to_number(dec_num, to_int?) do
    res = if Decimal.integer?(dec_num), do: dec_num, else: Decimal.round(dec_num, 8, :floor)

    if to_int? and Decimal.integer?(res),
      do: Decimal.to_integer(res),
      else: Decimal.to_float(res)
  end
end
