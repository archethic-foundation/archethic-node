defmodule Archethic.Contracts.Interpreter.ASTHelper do
  @moduledoc """
  Helper functions to manipulate AST
  """

  @doc """
  Return wether the given ast is a keyword list

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("[]")
    iex> ASTHelper.is_keyword_list?(ast)
    true

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("[sum: 1, product: 10]")
    iex> ASTHelper.is_keyword_list?(ast)
    true

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("[1,2,3]")
    iex> ASTHelper.is_keyword_list?(ast)
    false
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

  @doc """
  Return wether the given ast is a variable

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("hello")
    iex> ASTHelper.is_variable?(ast)
    true
  """
  @spec is_variable?(Macro.t()) :: boolean()
  def is_variable?({{:atom, _}, _, nil}), do: true
  def is_variable?(_), do: false

  @doc """
  Return wether the given ast is a function call or not

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("hello(12)")
    iex> ASTHelper.is_function_call?(ast)
    true

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("hello()")
    iex> ASTHelper.is_function_call?(ast)
    true

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("hello")
    iex> ASTHelper.is_function_call?(ast)
    false
  """
  @spec is_function_call?(Macro.t()) :: boolean()
  def is_function_call?({{:atom, _}, _, list}) when is_list(list), do: true
  def is_function_call?(_), do: false

  @doc """
  Convert a keyword AST into a map AST

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("[sum: 1, product: 10]")
    iex> Macro.to_string(ASTHelper.keyword_to_map(ast))
    ~s(%{"sum" => 1, "product" => 10})
  """
  @spec keyword_to_map(Macro.t()) :: Macro.t()
  def keyword_to_map(ast) do
    proplist =
      Enum.map(ast, fn {{:atom, atomName}, value} ->
        {atomName, value}
      end)

    {:%{}, [], proplist}
  end

  @doc """
  Maybe wrap the AST in a block if it's not already a block

  We use this because do..end blocks have 2 forms:
    - when there is a single expression in the block
        ex:
          {:if, _, _} (1)
    - when there are multiple expression in the block
        ex:
          {:__block__, [], [
            {:if, _, _},
            {:if, _, _}
          ]}

  We use it:
    - in if/else, in order to always have a __block__ to pattern match
    - in the ActionIntepreter's prewalk because we discard completely the rest of the code except the do..end block.
      If we don't wrap in a block and the code is a single expression, it would be automatically whitelisted.

    iex> ASTHelper.wrap_in_block({:if, [], [true, [do: 1, else: 2]]})
    iex> {:__block__, [], [{:if, [], [true, [do: 1, else: 2]]}]}

    iex> ASTHelper.wrap_in_block({:__block__, [], [{:if, [], [true, [do: 1, else: 2]]}]})
    iex> {:__block__, [], [{:if, [], [true, [do: 1, else: 2]]}]}
  """
  def wrap_in_block(ast = {:__block__, _, _}), do: ast
  def wrap_in_block(ast), do: {:__block__, [], [ast]}

  # --------------
  # DEBUG
  # --------------

  @doc """
  Return the AST of IO.inspect(var)
  """
  @spec io_inspect(Macro.t()) :: Macro.t()
  def io_inspect(var) do
    quote do: IO.inspect(unquote(var))
  end

  @doc """
  Return the AST of IO.inspect(var, label: label)
  """
  @spec io_inspect(Macro.t(), binary()) :: Macro.t()
  def io_inspect(var, label) do
    quote do: IO.inspect(unquote(var), label: unquote(label))
  end
end
