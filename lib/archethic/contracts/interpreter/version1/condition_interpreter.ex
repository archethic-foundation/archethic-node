defmodule Archethic.Contracts.Interpreter.Version1.ConditionInterpreter do
  @moduledoc false

  alias Archethic.Contracts.Interpreter.Version1.CommonInterpreter
  alias Archethic.Contracts.Interpreter.Version1.Library
  alias Archethic.Contracts.ContractConditions, as: Conditions
  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.Version0

  @modules_whitelisted Library.list_common_modules()

  @type condition_type :: :transaction | :inherit | :oracle

  @doc """
  Parse the given node and return the trigger and the actions block.
  """
  @spec parse(any()) ::
          {:ok, condition_type(), Conditions.t()} | {:error, any(), String.t()}
  def parse({{:atom, "condition"}, _, [[{{:atom, condition_name}, keyword}]]}) do
    # scope_key is used because we are using version0 conditionInterpreter
    {condition_type, scope_key} =
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
        # todo: throw if unknown key
        new_value = to_boolean_expression([scope_key, key], value)
        Map.put(acc, String.to_existing_atom(key), new_value)
      end)

    {:ok, condition_type, conditions}
  catch
    {:error, node} ->
      {:error, node, "unexpected term"}

    {:error, node, reason} ->
      {:error, node, reason}
  end

  def parse(node) do
    {:error, node, "unexpected term"}
  end

  @doc """
  Return true if the given conditions are valid on the given constants
  Here we can use version0 because the validation logic does not change.

  We'll just need to use the same scope as version0 to make it work. (to_boolean_expression does this)
  """
  @spec valid_conditions?(Conditions.t(), map()) :: bool()
  def valid_conditions?(conditions, constants) do
    Version0.ConditionInterpreter.valid_conditions?(
      conditions,
      constants
    )
  end

  # ----------------------------------------
  # We keep the scope similar to Version0 because there's no need for multiple scopes in the
  # condition block. Here we assume we have a `scope` variable in our bindings.
  #
  # `subject` is the "accessor" to the transaction for this condition
  defp to_boolean_expression(subject, value)
       when is_binary(value) or is_integer(value) or is_float(value) do
    # var!(scope) is used to say that scope variable is in the context=nil
    # (version0 use context=nil to store the bindings)
    quote do
      unquote(value) == get_in(var!(scope), unquote(subject))
    end
  end

  defp to_boolean_expression(subject, value) do
    Macro.postwalk(value, &postwalk(&1, subject))
  end

  # Module.function call
  # we override the CommonInterpreter behaviour to add the contract as first argument
  defp postwalk(
         node =
           {{:., meta, [{:__aliases__, _, [atom: module_name]}, {:atom, function_name}]}, _, args},
         subject
       )
       when module_name in @modules_whitelisted do
    # if function exist with arity => node
    arity = length(args)

    absolute_module_atom =
      String.to_existing_atom(
        "Elixir.Archethic.Contracts.Interpreter.Version1.Library.Common.#{module_name}"
      )

    cond do
      # check function is available with given arity
      Library.function_exists?(absolute_module_atom, function_name, arity) ->
        {new_node, nil} = CommonInterpreter.postwalk(node, nil)
        new_node

      # if function exist with arity+1 => prepend the key to args
      Library.function_exists?(absolute_module_atom, function_name, arity + 1) ->
        ast =
          quote do
            # var!(scope) is used to say that scope variable is in the context=nil
            # (version0 use context=nil to store the bindings)
            get_in(var!(scope), unquote(subject))
          end

        # add it as first function argument
        node_with_key_appended =
          {{:., meta, [{:__aliases__, meta, [atom: module_name]}, {:atom, function_name}]}, meta,
           [ast | args]}

        {new_node, nil} = CommonInterpreter.postwalk(node_with_key_appended, nil)
        new_node

      # check function exists
      Library.function_exists?(absolute_module_atom, function_name) ->
        throw({:error, node, "invalid arity for function #{module_name}.#{function_name}"})

      true ->
        throw({:error, node, "unknown function:  #{module_name}.#{function_name}"})
    end
  end

  # Dot access non-nested (x.y)
  defp postwalk(
         _node = {{:., _, [{{:atom, map_name}, _, nil}, {:atom, key_name}]}, _, _},
         _subject
       ) do
    quote do
      get_in(
        var!(scope),
        [unquote(map_name), unquote(key_name)]
      )
    end
  end

  # Dot access nested (x.y.z)
  defp postwalk({{:., _, [first_arg, {:atom, key_name}]}, _, []}, _subject) do
    quote do
      get_in(unquote(first_arg), [unquote(key_name)])
    end
  end

  # pass through
  defp postwalk(node, _subject) do
    node
  end
end
