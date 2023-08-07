defmodule Archethic.Contracts.Interpreter.Library.Common.String do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Tag
  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST

  use Tag

  @spec size(String.t()) :: integer()
  defdelegate size(str),
    to: String,
    as: :length

  @spec in?(String.t(), String.t()) :: boolean()
  defdelegate in?(str, substr),
    to: String,
    as: :contains?

  @spec to_hex(String.t()) :: String.t() | nil
  def to_hex(str) do
    case Base.decode16(str, case: :mixed) do
      {:ok, bin} ->
        Base.encode16(bin)

      :error ->
        Base.encode16(str)
    end
  end

  @spec to_uppercase(String.t()) :: String.t()
  defdelegate to_uppercase(str),
    to: String,
    as: :upcase

  @spec to_lowercase(String.t()) :: String.t()
  defdelegate to_lowercase(str),
    to: String,
    as: :downcase

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

  def check_types(:to_hex, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:to_uppercase, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:to_lowercase, [first]) do
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
    AST.is_number?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false
end
