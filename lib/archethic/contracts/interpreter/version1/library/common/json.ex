defmodule Archethic.Contracts.Interpreter.Version1.Library.Common.Json do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Version1.Library

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.Legacy

  @spec path_extract(String.t(), String.t()) :: String.t()
  defdelegate path_extract(text, path),
    to: Legacy.Library,
    as: :json_path_extract

  @spec path_match?(String.t(), String.t()) :: boolean()
  defdelegate path_match?(text, path),
    to: Legacy.Library,
    as: :json_path_match?

  @spec to_string(any()) :: String.t()
  defdelegate to_string(term),
    to: Jason,
    as: :encode!

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
      AST.is_float?(first) ||
      AST.is_integer?(first)
  end

  def check_types(:is_valid?, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false
end
