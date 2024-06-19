defmodule Archethic.Contracts.Interpreter.Library.Common.List do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library

  require Decimal
  alias Archethic.Tag
  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST

  use Tag

  @spec at(list(), integer() | Decimal.t()) :: any()
  def at(list, idx) do
    cond do
      is_integer(idx) ->
        Enum.at(list, idx)

      Decimal.is_decimal(idx) && Decimal.integer?(idx) ->
        Enum.at(list, Decimal.to_integer(idx))

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

  def check_types(_, _), do: false
end
