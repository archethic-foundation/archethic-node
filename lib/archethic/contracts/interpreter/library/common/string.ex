defmodule Archethic.Contracts.Interpreter.Library.Common.String do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Tag
  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Utils

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

  @spec to_number(String.t()) :: integer() | Decimal.t() | nil
  def to_number(string) do
    try do
      string
      |> Decimal.new()
      |> Utils.maybe_decimal_to_integer()
    rescue
      _ -> nil
    end
  end

  @spec from_number(integer() | Decimal.t()) :: String.t()
  def from_number(num) when is_integer(num), do: Integer.to_string(num)

  def from_number(num = %Decimal{}) do
    if Decimal.integer?(num) do
      # we display as an int if there is no decimals
      num |> Decimal.to_integer() |> Integer.to_string()
    else
      num |> Decimal.to_string()
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
