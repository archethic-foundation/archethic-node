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

  @spec to_number(String.t()) :: integer() | float() | nil
  def to_number(string) do
    try do
      String.to_integer(string)
    rescue
      _ ->
        try do
          String.to_float(string)
        rescue
          _ ->
            nil
        end
    end
  end

  @spec from_number(integer() | float()) :: String.t()
  def from_number(int) when is_integer(int) do
    Integer.to_string(int)
  end

  def from_number(float) when is_float(float) do
    truncated = trunc(float)

    # we display as an int if there is no decimals
    if truncated == float do
      Integer.to_string(truncated)
    else
      Float.to_string(float)
    end
  end

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:size, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:in?, [first, second]) do
    (AST.is_binary?(first) || AST.is_variable_or_function_call?(first)) &&
      (AST.is_binary?(second) || AST.is_variable_or_function_call?(second))
  end

  def check_types(:to_number, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:from_number, [first]) do
    AST.is_integer?(first) || AST.is_float?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false
end
