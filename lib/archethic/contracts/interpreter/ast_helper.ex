defmodule Archethic.Contracts.Interpreter.ASTHelper do
  @moduledoc """
  Helper functions to manipulate AST
  """

  @doc """
  Return wether the given ast is a keyword list.
  Remember that we convert all keywords to maps in the prewalk.

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("[]")
    iex> ASTHelper.is_keyword_list?(ast)
    false

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("[sum: 1, product: 10]")
    iex> ASTHelper.is_keyword_list?(ast)
    true

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("[1,2,3]")
    iex> ASTHelper.is_keyword_list?(ast)
    false
  """
  @spec is_keyword_list?(Macro.t()) :: boolean()
  def is_keyword_list?(ast = [_ | _]) do
    Enum.all?(ast, fn
      {{:atom, bin}, _value} when is_binary(bin) ->
        true

      _ ->
        false
    end)
  end

  def is_keyword_list?(_), do: false

  @doc """
  Return wether the given ast is a map

    iex> ast = quote do: %{"sum" => 1, "product" => 10}
    iex> ASTHelper.is_map?(ast)
    true
  """
  @spec is_map?(Macro.t()) :: boolean()
  def is_map?({:%{}, _, _}), do: true
  def is_map?(_), do: false

  @doc """
  Return wether the given ast is an integer

    iex> ast = quote do: 1
    iex> ASTHelper.is_number?(ast)
    true

    iex> ast = quote do: 1.01
    iex> ASTHelper.is_number?(ast)
    true
  """
  @spec is_number?(Macro.t()) :: boolean()
  def is_number?(node) do
    is_integer(node) || is_float(node)
  end

  @doc ~S"""
  Return wether the given ast is an binary

    iex> ast = quote do: "hello"
    iex> ASTHelper.is_binary?(ast)
    true

    iex> _hello = "hello"
    iex> ast = quote do: "#{_hello} world"
    iex> ASTHelper.is_binary?(ast)
    true
  """
  @spec is_binary?(Macro.t()) :: boolean()
  def is_binary?(node) when is_binary(node), do: true
  def is_binary?({:<<>>, _, _}), do: true
  def is_binary?(_), do: false

  @doc """
  Return wether the given ast is a a list

    iex> ast = quote do: [1, 2]
    iex> ASTHelper.is_list?(ast)
    true
  """
  @spec is_list?(Macro.t()) :: boolean()
  def is_list?(node), do: is_list(node)

  @doc """
  Return wether the given ast is a variable or a function call or a block.
  Useful because we pretty much accept this everywhere.

  We must accept blocks as well because we cannot determine its type.
  (If the user code 1+1 it will be a block)
  """
  @spec is_variable_or_function_call?(Macro.t()) :: boolean()
  def is_variable_or_function_call?(ast) do
    is_variable?(ast) || is_function_call?(ast) || is_block?(ast)
  end

  @doc """
  Return wether the given ast is a block
  """
  def is_block?({:__block__, _, _}), do: true
  def is_block?(_), do: false

  @doc """
  Return wether the given ast is a variable.
  Variable are transformed into {:get_in, _, _} in our prewalks

  TODO: find a elegant way to test this.
  """
  @spec is_variable?(Macro.t()) :: boolean()
  def is_variable?({:get_in, _, _}), do: true
  def is_variable?(_), do: false

  @doc """
  Return wether the given ast is a function call or not

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("hello(12)")
    iex> ASTHelper.is_function_call?(ast)
    true

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("hello()")
    iex> ASTHelper.is_function_call?(ast)
    true

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("Module.hello()")
    iex> ASTHelper.is_function_call?(ast)
    true

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("hello")
    iex> ASTHelper.is_function_call?(ast)
    false
  """
  @spec is_function_call?(Macro.t()) :: boolean()
  def is_function_call?({{:atom, _}, _, list}) when is_list(list), do: true
  def is_function_call?({{:., _, [{:__aliases__, _, _}, _]}, _, _}), do: true
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
      Enum.map(ast, fn {{:atom, atom_name}, value} ->
        {atom_name, value}
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

  @doc """
  Delegate the arithmetic to the Decimal library

  ## Example

    iex> ASTHelper.decimal_arithmetic(:+, 1, 2)
    3

    iex> ASTHelper.decimal_arithmetic(:+, 1.0, 2)
    3.0

    iex> ASTHelper.decimal_arithmetic(:+, 1, 2.2)
    3.2

    iex> ASTHelper.decimal_arithmetic(:/, 1, 2)
    0.5

    iex> ASTHelper.decimal_arithmetic(:*, 3, 4)
    12
  """
  @spec decimal_arithmetic(Macro.t(), number(), number()) :: float()
  def decimal_arithmetic(ast, lhs, rhs) do
    operation =
      case ast do
        :* -> &Decimal.mult/2
        :/ -> &Decimal.div/2
        :+ -> &Decimal.add/2
        :- -> &Decimal.sub/2
      end

    # If both operand are integer we return an integer if possible
    # otherwise a float is returned

    if is_integer(lhs) and is_integer(rhs) do
      lhs = Decimal.new(lhs)
      rhs = Decimal.new(rhs)

      res = operation.(lhs, rhs) |> decimal_round()
      if Decimal.integer?(res), do: Decimal.to_integer(res), else: Decimal.to_float(res)
    else
      # the `0.0 + x` is used to cast integers to floats
      lhs = Decimal.from_float(0.0 + lhs)
      rhs = Decimal.from_float(0.0 + rhs)

      operation.(lhs, rhs) |> decimal_round() |> Decimal.to_float()
    end
  end

  defp decimal_round(dec_num) do
    # Round only if number is not integer, otherwise there is some inconsisties with 0 or -0
    if Decimal.integer?(dec_num), do: dec_num, else: Decimal.round(dec_num, 8, :floor)
  end
end
