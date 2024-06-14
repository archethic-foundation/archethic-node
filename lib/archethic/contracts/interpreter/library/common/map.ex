defmodule Archethic.Contracts.Interpreter.Library.Common.Map do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Tag
  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST

  use Tag

  @spec new() :: map()
  defdelegate new(), to: Map

  @spec keys(map()) :: list(String.t())
  defdelegate keys(map), to: Map

  @spec values(map()) :: list(any())
  defdelegate values(map), to: Map

  @spec size(map()) :: integer()
  defdelegate size(map), to: Kernel, as: :map_size

  @spec get(map(), binary(), any()) :: any()
  defdelegate get(map, key, default \\ nil), to: Map

  @spec set(map(), binary(), any()) :: map()
  defdelegate set(map, key, value), to: Map, as: :put

  @spec delete(map(), binary()) :: map()
  defdelegate delete(map, key), to: Map

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:new, []) do
    true
  end

  def check_types(:keys, [first]) do
    AST.is_map?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:values, [first]) do
    AST.is_map?(first) || AST.is_variable_or_function_call?(first)
  end

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

  def check_types(:delete, [first, _second]) do
    AST.is_map?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false
end
