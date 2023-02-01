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
  Transform an ast that is a keyword list in a proplist
  (because we don't allow atom from user-code)

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("[]")
    iex> ASTHelper.keyword_to_proplist(ast)
    []

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("[sum: 1]")
    iex> ASTHelper.keyword_to_proplist(ast)
    [{"sum", 1}]

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("[sum: 1, product: 10]")
    iex> ASTHelper.keyword_to_proplist(ast)
    [{"sum", 1}, {"product", 10}]
  """
  @spec keyword_to_proplist(Macro.t()) :: :proplists.proplist()
  def keyword_to_proplist(ast) do
    Enum.map(ast, fn {{:atom, atomName}, value} ->
      {atomName, value}
    end)
  end

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
