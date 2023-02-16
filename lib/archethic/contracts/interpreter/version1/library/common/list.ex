defmodule Archethic.Contracts.Interpreter.Version1.Library.Common.List do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Version1.Library

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST

  @spec take_element_at_index(list(), integer()) :: any()
  defdelegate take_element_at_index(list, idx),
    to: Enum,
    as: :at

  @spec size(list()) :: integer()
  defdelegate size(list),
    to: Kernel,
    as: :length

  @spec in?(list(), any()) :: boolean()
  defdelegate in?(list, element),
    to: Enum,
    as: :member?

  @spec empty?(list()) :: boolean()
  defdelegate empty?(list),
    to: Enum,
    as: :empty?

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:take_element_at_index, [first, second]) do
    (AST.is_list?(first) || AST.is_variable_or_function_call?(first)) &&
      (AST.is_integer?(second) || AST.is_variable_or_function_call?(second))
  end

  def check_types(:size, [first]) do
    AST.is_list?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:in?, [first, _second]) do
    AST.is_list?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:empty?, [first]) do
    AST.is_list?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false
end
