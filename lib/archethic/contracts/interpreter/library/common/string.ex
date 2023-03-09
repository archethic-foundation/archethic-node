defmodule Archethic.Contracts.Interpreter.Library.Common.String do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST

  @spec size(String.t()) :: integer()
  defdelegate size(str),
    to: String,
    as: :length

  @spec in?(String.t(), String.t()) :: boolean()
  defdelegate in?(str, substr),
    to: String,
    as: :contains?

  @spec to_int(String.t()) :: integer()
  defdelegate to_int(str),
    to: String,
    as: :to_integer

  @spec from_int(integer()) :: String.t()
  defdelegate from_int(int),
    to: Integer,
    as: :to_string

  @spec to_float(String.t()) :: float()
  defdelegate to_float(str),
    to: String,
    as: :to_float

  @spec from_float(float()) :: String.t()
  defdelegate from_float(float),
    to: Float,
    as: :to_string

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:size, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:in?, [first, second]) do
    (AST.is_binary?(first) || AST.is_variable_or_function_call?(first)) &&
      (AST.is_binary?(second) || AST.is_variable_or_function_call?(second))
  end

  def check_types(:to_int, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:from_int, [first]) do
    AST.is_integer?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:to_float, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:from_float, [first]) do
    AST.is_float?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false
end
