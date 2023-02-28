defmodule Archethic.Contracts.Interpreter.Version1.Library.Common.Map do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Version1.Library

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST

  @spec size(map()) :: integer()
  def size(map) do
    length(Map.keys(map))
  end

  @spec get(map(), binary(), any()) :: any()
  defdelegate get(map, key, default \\ nil),
    to: Map

  @spec set(map(), binary(), any()) :: map()
  def set(map, key, value) do
    Map.update(map, key, value, fn _ ->
      value
    end)
  end

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:size, [first]) do
    AST.is_map?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:get, [first, second]) do
    (AST.is_map?(first) || AST.is_variable_or_function_call?(first)) &&
      (AST.is_binary?(second) || AST.is_variable_or_function_call?(second))
  end

  def check_types(:get, [first, second, _third]) do
    (AST.is_map?(first) || AST.is_variable_or_function_call?(first)) &&
      (AST.is_binary?(second) || AST.is_variable_or_function_call?(second))
  end

  def check_types(:set, [first, second, _third]) do
    (AST.is_map?(first) || AST.is_variable_or_function_call?(first)) &&
      (AST.is_binary?(second) || AST.is_variable_or_function_call?(second))
  end

  def check_types(_, _), do: false
end
