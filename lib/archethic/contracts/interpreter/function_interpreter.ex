defmodule Archethic.Contracts.Interpreter.FunctionInterpreter do
  @moduledoc false
  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.Scope
  alias Archethic.Contracts.Interpreter.CommonInterpreter
  require Logger

  @doc """
  Parse the given node and return the function name it's args as strings and the AST block.
  """
  @spec parse(ast :: any(), function_keys :: list(Interpreter.function_key())) ::
          {:ok, function_name :: binary(), args :: list(), function_ast :: any()}
          | {:error, node :: any(), reason :: binary()}
  def parse({{:atom, "fun"}, _, [{{:atom, function_name}, _, args}, [do: block]]}, functions_keys) do
    ast = parse_block(AST.wrap_in_block(block), functions_keys)
    args = parse_args(args)
    {:ok, function_name, args, ast}
  catch
    {:error, node} ->
      {:error, node, "unexpected term"}

    {:error, node, reason} ->
      {:error, node, reason}
  end

  def parse(
        {{:atom, "export"}, _,
         [{{:atom, "fun"}, _, [{{:atom, function_name}, _, args}]}, [do: block]]},
        functions_keys
      ) do
    ast = parse_block(AST.wrap_in_block(block), functions_keys)
    args = parse_args(args)

    {:ok, function_name, args, ast}
  catch
    {:error, node} ->
      {:error, node, "unexpected term"}

    {:error, node, reason} ->
      {:error, node, reason}
  end

  def parse(node, _) do
    {:error, node, "unexpected term"}
  end

  @doc """
  Execute function code and returns the result
  """
  @spec execute(ast :: any(), constants :: map()) :: result :: any()
  def execute(ast, constants, args_names \\ [], args_ast \\ []) do
    Scope.execute(ast, constants, args_names, args_ast)
  end

  # ----------------------------------------------------------------------
  #              _            _
  #   _ __  _ __(___   ____ _| |_ ___
  #  | '_ \| '__| \ \ / / _` | __/ _ \
  #  | |_) | |  | |\ V | (_| | ||  __/
  #  | .__/|_|  |_| \_/ \__,_|\__\___|
  #  |_|
  # ----------------------------------------------------------------------
  defp parse_block(ast, functions_keys) do
    # here the accumulator is an list of parent scopes & current scope
    # where we can access variables from all of them
    # `acc = [ref1]` means read variable from scope.ref1 or scope
    # `acc = [ref1, ref2]` means read variable from scope.ref1.ref2 or scope.ref1 or scope
    # function's args are added to the acc by the interpreter
    acc = []

    {new_ast, _} =
      Macro.traverse(
        ast,
        acc,
        fn node, acc ->
          prewalk(node, acc)
        end,
        fn node, acc ->
          postwalk(node, acc, functions_keys)
        end
      )

    new_ast
  end

  defp parse_args(nil), do: []

  defp parse_args(args) do
    Enum.map(args, fn {{:atom, arg}, _, _} -> arg end)
  end

  # ----------------------------------------------------------------------
  #                                _ _
  #   _ __  _ __ _____      ____ _| | | __
  #  | '_ \| '__/ _ \ \ /\ / / _` | | |/ /
  #  | |_) | | |  __/\ V  V | (_| | |   <
  #  | .__/|_|  \___| \_/\_/ \__,_|_|_|\_\
  #  |_|
  # ----------------------------------------------------------------------

  # Ban access to Contract module
  defp prewalk(
         node = {:__aliases__, _, [atom: "Contract"]},
         _
       ) do
    throw({:error, node, "Contract is not allowed in function"})
  end

  defp prewalk(
         node,
         acc
       ) do
    CommonInterpreter.prewalk(node, acc)
  end

  # ----------------------------------------------------------------------
  #                   _                 _ _
  #   _ __   ___  ___| |___      ____ _| | | __
  #  | '_ \ / _ \/ __| __\ \ /\ / / _` | | |/ /
  #  | |_) | (_) \__ | |_ \ V  V | (_| | |   <
  #  | .__/ \___/|___/\__| \_/\_/ \__,_|_|_|\_\
  #  |_|
  # ----------------------------------------------------------------------
  # --------------- catch all -------------------
  defp postwalk(node, acc, function_keys) do
    CommonInterpreter.postwalk(node, acc, function_keys)
  end
end
