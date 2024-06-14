defmodule Archethic.Contracts.Interpreter.Library.Common.Json do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Tag
  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.Legacy

  use Tag

  @spec path_extract(String.t(), String.t()) :: String.t()
  defdelegate path_extract(text, path),
    to: Legacy.Library,
    as: :json_path_extract

  @spec path_match?(String.t(), String.t()) :: boolean()
  defdelegate path_match?(text, path),
    to: Legacy.Library,
    as: :json_path_match?

  @spec to_string(any()) :: String.t()
  def to_string(term) do
    term
    |> decimals_to_numbers()
    |> Jason.encode!()
  end

  @spec parse(String.t()) :: any()
  def parse(text) do
    text |> Jason.decode!() |> floats_to_decimals()
  end

  @spec is_valid?(String.t()) :: boolean()
  def is_valid?(str) do
    case Jason.decode(str) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:path_extract, [first, second]) do
    (AST.is_binary?(first) || AST.is_variable_or_function_call?(first)) &&
      (AST.is_binary?(second) || AST.is_variable_or_function_call?(second))
  end

  def check_types(:path_match?, [first, second]) do
    (AST.is_binary?(first) || AST.is_variable_or_function_call?(first)) &&
      (AST.is_binary?(second) || AST.is_variable_or_function_call?(second))
  end

  def check_types(:to_string, [first]) do
    AST.is_binary?(first) ||
      AST.is_variable_or_function_call?(first) ||
      AST.is_map?(first) ||
      AST.is_list?(first) ||
      AST.is_number?(first)
  end

  def check_types(:is_valid?, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:parse, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false

  # this results in imprecision, only to be used with json which is also imprecise
  defp decimals_to_numbers(decimal = %Decimal{}) do
    if Decimal.integer?(decimal) do
      Decimal.to_integer(decimal)
    else
      Decimal.to_float(decimal)
    end
  end

  defp decimals_to_numbers(term) when is_list(term) do
    Enum.map(term, &decimals_to_numbers/1)
  end

  defp decimals_to_numbers(term) when is_map(term) do
    term
    |> Enum.map(fn {key, value} ->
      {key, decimals_to_numbers(value)}
    end)
    |> Enum.into(%{})
  end

  defp decimals_to_numbers(term), do: term

  defp floats_to_decimals(flt) when is_float(flt) do
    Decimal.from_float(flt)
  end

  defp floats_to_decimals(term) when is_list(term) do
    Enum.map(term, &floats_to_decimals/1)
  end

  defp floats_to_decimals(term) when is_map(term) do
    term
    |> Enum.map(fn {key, value} ->
      {key, floats_to_decimals(value)}
    end)
    |> Enum.into(%{})
  end

  defp floats_to_decimals(term), do: term
end
