defmodule Archethic.Contracts.Interpreter.ASTHelper do
  @moduledoc """
  Helper functions to manipulate AST
  """
  @spec is_keyword_list?(Macro.t()) :: boolean()
  def is_keyword_list?(ast) when is_list(ast) do
    Enum.all?(ast, fn
      {{:atom, bin}, _value} when is_binary(bin) ->
        true

      _ ->
        false
    end)
  end

  def is_keyword_list?(_), do: false

  @spec is_variable?(Macro.t()) :: boolean()
  def is_variable?({{:atom, _}, _, nil}), do: true
  def is_variable?(_), do: false

  @spec is_function_call?(Macro.t()) :: boolean()
  def is_function_call?({{:atom, _}, _, list}) when is_list(list), do: true
  def is_function_call?(_), do: false

  @spec is_list?(Macro.t()) :: boolean()
  def is_list?(ast), do: is_list(ast)

  # --------------
  # DEBUG
  # --------------

  @doc """
  Return the AST of IO.inspect(var)
  """
  @spec io_inspect(Macro.t()) :: Macro.t()
  def io_inspect(var) do
    {{:., [], [{:__aliases__, [alias: false], [:IO]}, :inspect]}, [], [var]}
  end

  @doc """
  Return the AST of IO.inspect(var, label: label)
  """
  @spec io_inspect(Macro.t(), binary()) :: Macro.t()
  def io_inspect(var, label) do
    {{:., [], [{:__aliases__, [alias: false], [:IO]}, :inspect]}, [], [var, [label: label]]}
  end
end
