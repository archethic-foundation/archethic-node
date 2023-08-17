defmodule Archethic.Contracts.Interpreter.ConditionInterpreter do
  @moduledoc false

  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.ContractConditions.Subjects, as: ConditionsSubjects
  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.CommonInterpreter
  alias Archethic.Contracts.Interpreter.FunctionKeys
  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.Contracts.Interpreter.Scope

  @condition_fields ConditionsSubjects.__struct__()
                    |> Map.keys()
                    |> Enum.reject(&(&1 == :__struct__))
                    |> Enum.map(&Atom.to_string/1)

  @doc """
  Parse the given node and return the trigger and the actions block.
  """
  @spec parse(any(), FunctionKeys.t()) ::
          {:ok, Contract.condition_type(), ConditionsSubjects.t()} | {:error, any(), String.t()}
  def parse(
        node = {{:atom, "condition"}, _, [[{{:atom, condition_name}, keyword}]]},
        functions_keys
      ) do
    case condition_name do
      "transaction" ->
        do_parse({:transaction, nil, nil}, keyword, functions_keys, node)

      "inherit" ->
        do_parse(:inherit, keyword, functions_keys, node)

      "oracle" ->
        do_parse(:oracle, keyword, functions_keys, node)

      _ ->
        {:error, node, "invalid condition type"}
    end
  end

  def parse(
        node =
          {{:atom, "condition"}, _,
           [
             {{:atom, "transaction"}, _, nil},
             [
               {{:atom, "on"}, {{:atom, action_name}, _, args}},
               {{:atom, "as"}, keyword}
             ]
           ]},
        functions_keys
      ) do
    args =
      case args do
        nil -> []
        _ -> Enum.map(args, fn {{:atom, arg_name}, _, nil} -> arg_name end)
      end

    do_parse({:transaction, action_name, args}, keyword, functions_keys, node)
  end

  def parse(node, _) do
    {:error, node, "unexpected term"}
  end

  # ----------------------------------------------------------------------
  #              _            _
  #   _ __  _ __(___   ____ _| |_ ___
  #  | '_ \| '__| \ \ / / _` | __/ _ \
  #  | |_) | |  | |\ V | (_| | ||  __/
  #  | .__/|_|  |_| \_/ \__,_|\__\___|
  #  |_|
  # ----------------------------------------------------------------------
  defp do_parse(condition_type, keyword, functions_keys, node) do
    global_variable =
      case condition_type do
        {:transaction, _, _} -> "transaction"
        :inherit -> "next"
        :oracle -> "transaction"
      end

    # no need to traverse the condition block
    # we'll traverse every block individually
    proplist =
      if keyword == [] or AST.is_keyword_list?(keyword) do
        {:%{}, _, proplist} = AST.keyword_to_map(keyword)
        proplist
      else
        throw({:error, node, "invalid condition block"})
      end

    conditions =
      Enum.reduce(proplist, %ConditionsSubjects{}, fn {key, value}, acc ->
        if key not in @condition_fields do
          throw({:error, node, "invalid condition field: #{key}"})
        end

        new_value = to_boolean_expression([global_variable, key], value, functions_keys)
        Map.put(acc, String.to_existing_atom(key), new_value)
      end)

    {:ok, condition_type, conditions}
  catch
    {:error, node} ->
      {:error, node, "unexpected term"}

    {:error, node, reason} ->
      {:error, node, reason}
  end

  defp to_boolean_expression(_subject, bool, _) when is_boolean(bool) do
    bool
  end

  # `subject` is the "accessor" to the transaction's property for this expression
  #
  # Example:
  #
  #   condition inherit: [
  #     content: "ciao"
  #   ]
  #
  #   - `subject == ["next", "content"]`
  #   - `value == "ciao"`
  #
  defp to_boolean_expression(subject, value, _)
       when is_binary(value) or is_integer(value) or is_float(value) do
    quote do
      unquote(value) == Scope.read_global(unquote(subject))
    end
  end

  defp to_boolean_expression(subject, ast, functions_keys) do
    acc = %{
      functions: functions_keys
    }

    {new_ast, _} =
      Macro.traverse(
        AST.wrap_in_block(ast),
        acc,
        fn node, acc ->
          prewalk(node, acc)
        end,
        fn node, acc ->
          postwalk(subject, node, acc)
        end
      )

    new_ast
  end

  # ----------------------------------------------------------------------
  #                                _ _
  #   _ __  _ __ _____      ____ _| | | __
  #  | '_ \| '__/ _ \ \ /\ / / _` | | |/ /
  #  | |_) | | |  __/\ V  V | (_| | |   <
  #  | .__/|_|  \___| \_/\_/ \__,_|_|_|\_\
  #  |_|
  # ----------------------------------------------------------------------

  # Here we check arity and arity + 1 since we can automatically fill the first parameter
  # with the subject of the condition
  defp prewalk(
         node =
           {{:., _meta, [{:__aliases__, _, [atom: module_name]}, {:atom, function_name}]}, _,
            args},
         acc
       ) do
    arity = length(args)

    if Library.function_tagged_with?(module_name, function_name, :write_contract),
      do: throw({:error, node, "Write contract functions are not allowed in condition block"})

    with {:error, :invalid_function_arity, _} <-
           Library.validate_module_call(module_name, function_name, arity),
         :ok <- Library.validate_module_call(module_name, function_name, arity + 1) do
      {node, acc}
    else
      {:error, _reason, message} -> throw({:error, node, message})
      :ok -> {node, acc}
    end
  end

  defp prewalk(node = {{:atom, function_name}, _, args}, acc = %{functions: functions})
       when is_list(args) and function_name != "for" do
    args_arity = length(args)

    cond do
      FunctionKeys.exist?(functions, function_name, args_arity) -> {node, acc}
      FunctionKeys.exist?(functions, function_name, args_arity + 1) -> {node, acc}
      true -> CommonInterpreter.prewalk(node, acc)
    end
  end

  defp prewalk(node, acc), do: CommonInterpreter.prewalk(node, acc)

  # ----------------------------------------------------------------------
  #                   _                 _ _
  #   _ __   ___  ___| |___      ____ _| | | __
  #  | '_ \ / _ \/ __| __\ \ /\ / / _` | | |/ /
  #  | |_) | (_) \__ | |_ \ V  V | (_| | |   <
  #  | .__/ \___/|___/\__| \_/\_/ \__,_|_|_|\_\
  #  |_|
  # ----------------------------------------------------------------------
  # Override custom function calls
  # because we might need to inject the contract as first argument
  defp postwalk(
         subject,
         node = {{:atom, function_name}, meta, args},
         acc = %{functions: functions}
       )
       when is_list(args) and function_name != "for" do
    arity = length(args)

    new_node =
      cond do
        FunctionKeys.exist?(functions, function_name, arity) ->
          {new_node, _} = CommonInterpreter.postwalk(node, acc)
          new_node

        # if function exist with arity+1 => prepend the key to args
        FunctionKeys.exist?(functions, function_name, arity + 1) ->
          ast =
            quote do
              Scope.read_global(unquote(subject))
            end

          # add ast as first function argument
          node_subject_appened = {{:atom, function_name}, meta, [ast | args]}

          {new_node, _} = CommonInterpreter.postwalk(node_subject_appened, acc)
          new_node
      end

    {new_node, acc}
  end

  # Override Module.function call
  # because we might need to inject the contract as first argument
  defp postwalk(
         subject,
         node =
           {{:., meta, [{:__aliases__, _, [atom: module_name]}, {:atom, function_name}]}, _, args},
         acc
       ) do
    # Module and function has already been verified do we get search for the good arity
    case Library.validate_module_call(module_name, function_name, length(args)) do
      :ok ->
        CommonInterpreter.postwalk(node, acc)

      {:error, :invalid_function_arity, _} ->
        ast =
          quote do
            Scope.read_global(unquote(subject))
          end

        # add it as first function argument
        node_with_key_appended =
          {{:., meta, [{:__aliases__, meta, [atom: module_name]}, {:atom, function_name}]}, meta,
           [ast | args]}

        CommonInterpreter.postwalk(node_with_key_appended, acc)
    end
  end

  defp postwalk(_subject, node, acc) do
    CommonInterpreter.postwalk(node, acc)
  end
end
