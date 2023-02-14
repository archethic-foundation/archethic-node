defmodule Archethic.Contracts.Interpreter.Version1.Library.Common.Map do
  @moduledoc false

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST

  @spec size(map()) :: integer()
  def size(map) do
    length(Map.keys(map))
  end

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:size, [first]) do
    AST.is_map?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false
end
