defmodule Archethic.Contracts.Interpreter.Library.Common.List do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Tag
  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST

  use Tag

  @spec at(list(), integer() | float()) :: any()
  def at(list, idx) do
    cond do
      is_integer(idx) ->
        Enum.at(list, idx)

      is_float(idx) && trunc(idx) == idx ->
        Enum.at(list, trunc(idx))

      true ->
        raise %FunctionClauseError{
          args: [list, idx],
          arity: 2,
          function: :at,
          module: __MODULE__
        }
    end
  end

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

  @spec concat(list(list())) :: list()
  defdelegate concat(list),
    to: Enum,
    as: :concat

  @spec join(list(), String.t()) :: String.t()
  defdelegate join(list, separator),
    to: Enum,
    as: :join

  @spec append(list(), any()) :: list()
  def append(list, element) do
    list ++ [element]
  end

  @spec prepend(list(), any()) :: list()
  def prepend(list, element) do
    [element | list]
  end

  @spec sort_by(list(), String.t()) :: list()
  def sort_by(list, key) do
    Enum.sort_by(list, & &1[key])
  end

  @spec uniq(list()) :: list()
  defdelegate uniq(list),
    to: Enum

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:at, [first, second]) do
    (AST.is_list?(first) || AST.is_variable_or_function_call?(first)) &&
      (AST.is_number?(second) || AST.is_variable_or_function_call?(second))
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

  def check_types(:concat, [first]) do
    AST.is_list?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:join, [first, second]) do
    (AST.is_list?(first) || AST.is_variable_or_function_call?(first)) &&
      (AST.is_binary?(second) || AST.is_variable_or_function_call?(second))
  end

  def check_types(:append, [first, _second]) do
    AST.is_list?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:prepend, [first, _second]) do
    AST.is_list?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:sort_by, [first, second]) do
    (AST.is_list?(first) || AST.is_variable_or_function_call?(first)) &&
      (AST.is_binary?(second) || AST.is_variable_or_function_call?(second))
  end

  def check_types(:uniq, [first]) do
    AST.is_list?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false
end
