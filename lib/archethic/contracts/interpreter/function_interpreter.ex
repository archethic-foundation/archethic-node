defmodule Archethic.Contracts.Interpreter.FunctionInterpreter do
  @moduledoc false

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.CommonInterpreter
  alias Archethic.Contracts.Interpreter.FunctionKeys
  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.Contracts.Interpreter.Scope

  require Logger

  @doc """
  Parse the given node and return the function name it's args as strings and the AST block.
  """
  @spec parse(ast :: any(), function_keys :: FunctionKeys.t()) ::
          {:ok, function_name :: binary(), args_names :: list(), function_ast :: any()}
          | {:error, node :: any(), reason :: binary()}
  def parse({{:atom, "fun"}, _, [{{:atom, function_name}, _, args}, [do: block]]}, functions_keys) do
    ast = parse_block(AST.wrap_in_block(block), functions_keys, false)
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
    ast = parse_block(AST.wrap_in_block(block), functions_keys, true)
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
  Execute public function code and returns the result

  Raise on SC's errors and timeout
  """
  @spec execute(ast :: any(), constants :: map(), args_names :: list(), args_values :: list()) ::
          result :: any()
  def execute(ast, constants, args_names \\ [], args_values \\ []) do
    Scope.execute(ast, constants, args_names, args_values)
  end

  # ----------------------------------------------------------------------
  #              _            _
  #   _ __  _ __(___   ____ _| |_ ___
  #  | '_ \| '__| \ \ / / _` | __/ _ \
  #  | |_) | |  | |\ V | (_| | ||  __/
  #  | .__/|_|  |_| \_/ \__,_|\__\___|
  #  |_|
  # ----------------------------------------------------------------------
  defp parse_block(ast, functions_keys, is_public?) do
    acc = %{
      functions: functions_keys
    }

    {new_ast, _} =
      Macro.traverse(
        ast,
        acc,
        fn node, acc ->
          prewalk(node, acc, is_public?)
        end,
        fn node, acc ->
          postwalk(node, acc)
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

  # Blacklist write_contract and IO function
  defp prewalk(
         node =
           {{:., _meta, [{:__aliases__, _, [atom: module_name]}, {:atom, function_name}]}, _,
            args},
         acc,
         public?
       ) do
    if Library.function_tagged_with?(module_name, function_name, :write_contract),
      do: throw({:error, node, "Write contract functions are not allowed in custom functions"})

    if Library.function_tagged_with?(module_name, function_name, :write_state),
      do: throw({:error, node, "Modifying contract's state is not allowed in custom functions"})

    if public? and Library.function_tagged_with?(module_name, function_name, :io),
      do: throw({:error, node, "IO function calls not allowed in public functions"})

    case Library.validate_module_call(module_name, function_name, length(args)) do
      :ok -> :ok
      {:error, _reason, message} -> throw({:error, node, message})
    end

    {node, acc}
  end

  # throw
  defp prewalk({{:atom, "throw"}, _, [reason]}, acc, _visibility) when is_binary(reason) do
    {{:throw, [context: Elixir, imports: [{1, Kernel}]], [reason]}, acc}
  end

  defp prewalk(node = {{:atom, function_name}, _, args}, _acc, true)
       when is_list(args) and function_name != "for",
       do: throw({:error, node, "not allowed to call function from public function"})

  defp prewalk(node = {{:atom, function_name}, _, args}, acc = %{functions: functions}, false)
       when is_list(args) and function_name != "for" do
    arity = length(args)

    if FunctionKeys.exist?(functions, function_name, arity) and
         FunctionKeys.private?(functions, function_name, arity) do
      throw({:error, node, "not allowed to call private function from a private function"})
    else
      CommonInterpreter.prewalk(node, acc)
    end
  end

  defp prewalk(
         node,
         acc,
         _visibility
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
  defp postwalk(node, acc) do
    CommonInterpreter.postwalk(node, acc)
  end
end
