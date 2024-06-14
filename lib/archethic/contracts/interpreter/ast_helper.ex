defmodule Archethic.Contracts.Interpreter.ASTHelper do
  @moduledoc """
  Helper functions to manipulate AST
  """

  alias Archethic.Utils

  @doc """
  Return wether the given ast is a keyword list.
  Remember that we convert all keywords to maps in the prewalk.

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("[]")
    ...> ASTHelper.is_keyword_list?(ast)
    false

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("[sum: 1, product: 10]")
    ...> ASTHelper.is_keyword_list?(ast)
    true

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("[1,2,3]")
    ...> ASTHelper.is_keyword_list?(ast)
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
  Return wether the given ast is a bool

    iex> ast = quote do: true
    ...> ASTHelper.is_boolean?(ast)
    true

    iex> ast = quote do: false
    ...> ASTHelper.is_boolean?(ast)
    true

    iex> ast = quote do: %{"sum" => 1, "product" => 10}
    ...> ASTHelper.is_boolean?(ast)
    false
  """
  @spec is_boolean?(Macro.t()) :: boolean()
  def is_boolean?(arg), do: is_boolean(arg)

  @doc """
  Return wether the given ast is a map

    iex> ast = quote do: %{"sum" => 1, "product" => 10}
    ...> ASTHelper.is_map?(ast)
    true
  """
  @spec is_map?(Macro.t()) :: boolean()
  def is_map?({:%{}, _, _}), do: true
  def is_map?(_), do: false

  @doc """
  Return wether the given ast is a number
  Every numbers are automatically converted to Decimal in the tokenization

    iex> ast = quote do: Decimal.new(1)
    ...> ASTHelper.is_number?(ast)
    true

    iex> ast = quote do: Decimal.new("1.01")
    ...> ASTHelper.is_number?(ast)
    true

    iex> ast = quote do: 100_012_030
    ...> ASTHelper.is_number?(ast)
    true

    iex> ast = quote do: []
    ...> ASTHelper.is_number?(ast)
    false
  """
  @spec is_number?(Macro.t()) :: boolean()
  def is_number?(num) when is_integer(num), do: true

  def is_number?({{:., _, [{:__aliases__, _, [:Decimal]}, :new]}, _, [_]}) do
    true
  end

  def is_number?({:try, _, [[do: {_, _, [op, _, _]}, rescue: _]]}) when op in [:+, :-, :/, :*] do
    true
  end

  def is_number?(_), do: false

  @doc """
  Extract the value of a Decimal.new()

  Used when we pattern match @version and action/condition's datetime
  """
  @spec decimal_to_integer(Macro.t()) :: integer() | :error
  def decimal_to_integer({{:., _, [{:__aliases__, _, [:Decimal]}, :new]}, _, [value]})
      when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> :error
    end
  end

  def decimal_to_integer({{:., _, [{:__aliases__, _, [:Decimal]}, :new]}, _, [value]})
      when is_integer(value) do
    value
  end

  def decimal_to_integer(_), do: :error

  @doc ~S"""
  Return wether the given ast is an binary

    iex> ast = quote do: "hello"
    ...> ASTHelper.is_binary?(ast)
    true

    iex> _hello = "hello"
    ...> ast = quote do: "#{_hello} world"
    ...> ASTHelper.is_binary?(ast)
    true
  """
  @spec is_binary?(Macro.t()) :: boolean()
  def is_binary?(node) when is_binary(node), do: true
  def is_binary?({:<<>>, _, _}), do: true
  def is_binary?(_), do: false

  @doc """
  Return wether the given ast is a a list

    iex> ast = quote do: [1, 2]
    ...> ASTHelper.is_list?(ast)
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
    # because numbers are Decimal struct, we need to exclude it
    # (because it would be the same as is_function_call?)
    not is_number?(ast) && (is_variable?(ast) || is_function_call?(ast) || is_block?(ast))
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
    ...> ASTHelper.is_function_call?(ast)
    true

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("hello()")
    ...> ASTHelper.is_function_call?(ast)
    true

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("Module.hello()")
    ...> ASTHelper.is_function_call?(ast)
    true

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("hello")
    ...> ASTHelper.is_function_call?(ast)
    false
  """
  @spec is_function_call?(Macro.t()) :: boolean()
  def is_function_call?({{:atom, _}, _, list}) when is_list(list), do: true
  def is_function_call?({{:., _, [{:__aliases__, _, _}, _]}, _, _}), do: true
  def is_function_call?(_), do: false

  @doc """
  Convert a keyword AST into a map AST

    iex> {:ok, ast} = Archethic.Contracts.Interpreter.sanitize_code("[sum: 1, product: 10]")
    ...> Macro.to_string(ASTHelper.keyword_to_map(ast))
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
    ...> {:__block__, [], [{:if, [], [true, [do: 1, else: 2]]}]}

    iex> ASTHelper.wrap_in_block({:__block__, [], [{:if, [], [true, [do: 1, else: 2]]}]})
    ...> {:__block__, [], [{:if, [], [true, [do: 1, else: 2]]}]}
  """
  def wrap_in_block(ast = {:__block__, _, _}), do: ast
  def wrap_in_block(ast), do: {:__block__, [], [ast]}

  @doc """
  Delegate the arithmetic to the Decimal library

  ## Example

    iex> ASTHelper.decimal_arithmetic(:+, Decimal.new(1), Decimal.new(2))
    ...> |> Decimal.eq?(Decimal.new(3)
    true

    iex> ASTHelper.decimal_arithmetic(:+, Decimal.new("1.0"), Decimal.new(2))
    ...> |> Decimal.eq?(Decimal.new(3)
    true

    iex> ASTHelper.decimal_arithmetic(:+, Decimal.new(1), Decimal.new("2.2"))
    ...> |> Decimal.eq?(Decimal.new("3.2")
    true

    iex> ASTHelper.decimal_arithmetic(:/, Decimal.new(1), Decimal.new(2))
    ...> |> Decimal.eq?(Decimal.new("0.5")
    true

    iex> ASTHelper.decimal_arithmetic(:*, Decimal.new(3), Decimal.new(4))
    ...> |> Decimal.eq?(Decimal.new(12)
    true
  """
  @spec decimal_arithmetic(Macro.t(), Decimal.t(), Decimal.t()) :: Decimal.t()
  def decimal_arithmetic(ast, lhs, rhs) do
    operation =
      case ast do
        :* -> &Decimal.mult/2
        :/ -> &Decimal.div/2
        :+ -> &Decimal.add/2
        :- -> &Decimal.sub/2
      end

    operation.(lhs, rhs)
    |> decimal_round()
    |> Utils.maybe_decimal_to_integer()
  end

  defp decimal_round(dec_num) do
    # Round only if number is not integer, otherwise there is some inconsisties with 0 or -0
    if Decimal.integer?(dec_num), do: dec_num, else: Decimal.round(dec_num, 8, :floor)
  end
end
