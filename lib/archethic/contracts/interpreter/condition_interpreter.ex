defmodule Archethic.Contracts.Interpreter.ConditionInterpreter do
  @moduledoc false

  alias Archethic.Contracts.Interpreter.CommonInterpreter
  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.Contracts.Interpreter.Scope
  alias Archethic.Contracts.ContractConditions, as: Conditions
  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter

  @modules_whitelisted Library.list_common_modules()
  @condition_fields Conditions.__struct__()
                    |> Map.keys()
                    |> Enum.reject(&(&1 == :__struct__))
                    |> Enum.map(&Atom.to_string/1)

  @type condition_type :: :transaction | :inherit | :oracle

  @doc """
  Parse the given node and return the trigger and the actions block.
  """
  @spec parse(any(), list(Interpreter.function_key())) ::
          {:ok, condition_type(), Conditions.t()} | {:error, any(), String.t()}
  def parse(
        node = {{:atom, "condition"}, _, [[{{:atom, condition_name}, keyword}]]},
        functions_keys
      ) do
    {condition_type, global_variable} =
      case condition_name do
        "transaction" -> {:transaction, "transaction"}
        "inherit" -> {:inherit, "next"}
        "oracle" -> {:oracle, "transaction"}
        _ -> throw({:error, "invalid condition type"})
      end

    # no need to traverse the condition block
    # we'll traverse every block individually
    {:%{}, _, proplist} = AST.keyword_to_map(keyword)

    conditions =
      Enum.reduce(proplist, %Conditions{}, fn {key, value}, acc ->
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
    # here the accumulator is an list of parent scopes & current scope
    # where we can access variables from all of them
    # `acc = [ref1]` means read variable from scope.ref1 or scope
    # `acc = [ref1, ref2]` means read variable from scope.ref1.ref2 or scope.ref1 or scope
    acc = []

    {new_ast, _} =
      Macro.traverse(
        AST.wrap_in_block(ast),
        acc,
        fn node, acc ->
          prewalk(subject, node, acc)
        end,
        fn node, acc ->
          postwalk(subject, node, acc, functions_keys)
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
  defp prewalk(_subject, node, acc) do
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
  # Override custom function calls
  # because we might need to inject the contract as first argument
  defp postwalk(subject, node = {{:atom, function_name}, meta, args}, acc, function_keys)
       when is_list(args) and function_name != "for" do
    arity = length(args)

    new_node =
      cond do
        Enum.member?(function_keys, {function_name, arity}) ->
          {new_node, _} = CommonInterpreter.postwalk(node, acc, function_keys)
          new_node

        # if function exist with arity+1 => prepend the key to args
        Enum.member?(function_keys, {function_name, arity + 1}) ->
          ast =
            quote do
              Scope.read_global(unquote(subject))
            end

          # add ast as first function argument
          node_subject_appened = {{:atom, function_name}, meta, [ast | args]}

          {new_node, _} = CommonInterpreter.postwalk(node_subject_appened, acc, function_keys)
          new_node

        true ->
          reason = "The function #{function_name}/#{Integer.to_string(arity)} does not exist"

          throw({:error, node, reason})
      end

    {new_node, acc}
  end

  # Override Module.function call
  # because we might need to inject the contract as first argument
  defp postwalk(
         subject,
         node =
           {{:., meta, [{:__aliases__, _, [atom: module_name]}, {:atom, function_name}]}, _, args},
         acc,
         function_keys
       )
       when module_name in @modules_whitelisted do
    # if function exist with arity => node
    arity = length(args)

    absolute_module_atom =
      String.to_existing_atom(
        "Elixir.Archethic.Contracts.Interpreter.Library.Common.#{module_name}"
      )

    new_node =
      cond do
        # check function is available with given arity
        Library.function_exists?(absolute_module_atom, function_name, arity) ->
          {new_node, _} = CommonInterpreter.postwalk(node, acc, function_keys)
          new_node

        # if function exist with arity+1 => prepend the key to args
        Library.function_exists?(absolute_module_atom, function_name, arity + 1) ->
          ast =
            quote do
              Scope.read_global(unquote(subject))
            end

          # add it as first function argument
          node_with_key_appended =
            {{:., meta, [{:__aliases__, meta, [atom: module_name]}, {:atom, function_name}]},
             meta, [ast | args]}

          {new_node, _} = CommonInterpreter.postwalk(node_with_key_appended, acc, function_keys)
          new_node

        # check function exists
        Library.function_exists?(absolute_module_atom, function_name) ->
          throw({:error, node, "invalid arity for function #{module_name}.#{function_name}"})

        true ->
          throw({:error, node, "unknown function:  #{module_name}.#{function_name}"})
      end

    {new_node, acc}
  end

  defp postwalk(_subject, node, acc, functions_keys) do
    CommonInterpreter.postwalk(node, acc, functions_keys)
  end
end
