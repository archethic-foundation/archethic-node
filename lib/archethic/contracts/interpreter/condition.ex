defmodule Archethic.Contracts.ConditionInterpreter do
  @moduledoc false

  alias Archethic.Contracts.Contract.Conditions
  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.Contracts.Interpreter.Utils, as: InterpreterUtils

  @condition_fields Conditions.__struct__()
                    |> Map.keys()
                    |> Enum.reject(&(&1 == :__struct__))
                    |> Enum.map(&Atom.to_string/1)

  @transaction_fields InterpreterUtils.transaction_fields()

  @library_functions_names Library.__info__(:functions)
                           |> Enum.map(&Atom.to_string(elem(&1, 0)))
  @doc ~S"""
  Parse a condition block

  ## Examples

    iex> ConditionInterpreter.parse({{:atom, "condition"}, [line: 1], 
    ...> [
    ...>  [
    ...>    {{:atom, "transaction"}, [
    ...>      {{:atom, "content"}, "hello"}
    ...>    ]}
    ...>  ]
    ...> ]})
    {:ok, %{
      transaction: %Conditions{
        content: {:==, [], [
          {:get_in, [], [
            {:scope, [], nil}, 
            ["transaction", "content"]
          ]},
          "hello"
         ]}
        }
      }
    }

    # Usage of functions in the condition fields

    iex> ConditionInterpreter.parse({{:atom, "condition"}, [line: 1],
    ...> [
    ...>  [
    ...>    {{:atom, "transaction"},  [
    ...>      {{:atom, "content"}, {{:atom, "hash"}, [line: 2],
    ...>       [
    ...>         {{:., [line: 2],
    ...>           [
    ...>             { {:atom, "contract"}, [line: 2],
    ...>              nil},
    ...>             {:atom, "code"}
    ...>           ]},
    ...>          [no_parens: true, line: 2],
    ...>          []}
    ...>       ]}
    ...>    }]}
    ...>  ]
    ...> ]})
    {
      :ok, %{ 
        transaction: %Conditions{
          content:  {:==, [line: 2], [
             {:get_in, [line: 2], [
               {:scope, [line: 2], nil}, 
               ["transaction", "content"]
             ]},
             {
               {:., [line: 2], [
                 {:__aliases__, [alias: Archethic.Contracts.Interpreter.Library], [:Library]}, 
                 :hash
               ]}, [line: 2], [
                 {:get_in, [line: 2], [
                   {:scope, [line: 2], nil}, 
                   ["contract", "code"]
                 ]}
               ]
              }
            ]
          }
        }
      }
    }

    # Usage with multiple condition fields

    iex> ConditionInterpreter.parse({{:atom, "condition"}, [line: 1],
    ...> [
    ...>   {{:atom, "transaction"}, [
    ...>     {{:atom, "content"}, "hello"},
    ...>     {{:atom, "uco_transfers"}, {:%{}, [line: 3],
    ...>      [
    ...>        {"00006B368BE45DACD0CBC0EC5893BDC1079448181AA88A2CBB84AF939912E858843E",
    ...>         1000000000}
    ...>      ]}
    ...>     }
    ...>   ]}
    ...> ]})
    {:ok, %{
      transaction: %Conditions{
        content: {:==, [], [{:get_in, [], [{:scope, [], nil}, ["transaction", "content"]]}, "hello"]},
        uco_transfers:  {:==, [], [
          {:get_in, [], [{:scope, [], nil}, 
            ["transaction", "uco_transfers"]
          ]},
          {:%{}, [line: 3], [{
            <<0, 0, 107, 54, 139, 228, 93, 172, 208, 203, 192, 236, 88, 147, 189, 193, 7, 148, 72, 24, 26, 168, 138, 44, 187, 132, 175, 147, 153, 18, 232, 88, 132, 62>>, 1000000000
          }]}
        ]}
      }
    }}

  """
  def parse(ast) do
    try do
      case Macro.traverse(
             ast,
             {:ok, %{scope: :root, conditions: %{}}},
             &prewalk(&1, &2),
             &postwalk/2
           ) do
        {{:atom, key}, :error} ->
          {:error, InterpreterUtils.format_error_reason({[], "unexpected term", key})}

        {{{:atom, key}, _}, :error} ->
          {:error, InterpreterUtils.format_error_reason({[], "unexpected term", key})}

        {{{:atom, key}, metadata, _}, :error} ->
          {:error, InterpreterUtils.format_error_reason({metadata, "unexpected term", key})}

        {{_, metadata, _}, {:error, reason}} ->
          {:error, InterpreterUtils.format_error_reason({metadata, "unexpected term", reason})}

        {_node, {:ok, %{conditions: conditions}}} ->
          {:ok, conditions}
      end
    catch
      {:error, {{:atom, key}, metadata, _}} ->
        {:error, InterpreterUtils.format_error_reason({metadata, "unexpected term", key})}
    end
  end

  # Whitelist the DSL for conditions
  defp prewalk(
         node = {{:atom, "condition"}, _metadata, _},
         {:ok, context = %{scope: :root}}
       ) do
    {node, {:ok, %{context | scope: :condition}}}
  end

  # Whitelist the transaction/inherit/oracle conditions
  defp prewalk(node = {{:atom, condition_name}, rest}, {:ok, context = %{scope: :condition}})
       when condition_name in ["transaction", "inherit", "oracle"] and is_list(rest),
       do:
         {node, {:ok, %{context | scope: {:condition, String.to_existing_atom(condition_name)}}}}

  # Whitelist the transaction fields in the conditions
  defp prewalk(
         node = {{:atom, field}, _},
         {:ok, context = %{scope: {:condition, condition_name}}}
       )
       when field in @condition_fields do
    {node, {:ok, %{context | scope: {:condition, condition_name, field}}}}
  end

  # Whitelist the library functions in the the field of a condition
  defp prewalk(
         node = {{:atom, function}, _metadata, _},
         {:ok, context = %{scope: parent_scope = {:condition, _, _}}}
       )
       when function in @library_functions_names do
    {node, {:ok, %{context | scope: {:function, function, parent_scope}}}}
  end

  # Whitelist usage of maps in the field of a condition
  defp prewalk(node = {{:atom, _key}, _val}, acc = {:ok, %{scope: {:condition, _, _}}}) do
    {node, acc}
  end

  defp prewalk(node, acc) do
    InterpreterUtils.prewalk(node, acc)
  end

  defp postwalk(node, :error), do: {node, :error}

  defp postwalk(
         node = {{:atom, "condition"}, _, [[{{:atom, condition_name}, conditions}]]},
         {:ok, context = %{conditions: previous_conditions}}
       ) do
    new_conditions = new_conditions(condition_name, conditions, previous_conditions)
    {node, {:ok, %{context | conditions: new_conditions}}}
  end

  defp postwalk(
         node = {{:atom, "condition"}, _, [{{:atom, condition_name}, conditions}]},
         {:ok, context = %{conditions: previous_conditions}}
       ) do
    new_conditions = new_conditions(condition_name, conditions, previous_conditions)
    {node, {:ok, %{context | conditions: new_conditions}}}
  end

  defp postwalk(
         node =
           {{:atom, "condition"}, _,
            [
              {{:atom, condition_name}, _,
               [
                 conditions
               ]}
            ]},
         {:ok, context = %{scope: %{conditions: previous_conditions}}}
       ) do
    new_conditions = new_conditions(condition_name, conditions, previous_conditions)
    {node, {:ok, %{context | conditions: new_conditions}}}
  end

  defp postwalk(
         node = {{:atom, field}, _},
         {:ok, context = %{scope: {:condition, condition_name, field}}}
       )
       when field in @condition_fields do
    {node, {:ok, %{context | scope: {:condition, condition_name}}}}
  end

  defp postwalk(
         node = {{:atom, condition_name}, _},
         {:ok, context = %{scope: {:condition, _}}}
       )
       when condition_name in ["transaction", "inherit", "oracle"] do
    {node, {:ok, %{context | scope: :condition}}}
  end

  defp postwalk(node, acc) do
    InterpreterUtils.postwalk(node, acc)
  end

  defp new_conditions(condition_name, conditions, previous_conditions) do
    bindings = Enum.map(@transaction_fields, &{&1, ""}) |> Enum.into(%{})

    bindings =
      case condition_name do
        "inherit" ->
          Map.merge(bindings, %{
            "next" => Enum.map(@transaction_fields, &{&1, ""}) |> Enum.into(%{}),
            "previous" => Enum.map(@transaction_fields, &{&1, ""}) |> Enum.into(%{})
          })

        _ ->
          Map.merge(bindings, %{
            "contract" => Enum.map(@transaction_fields, &{&1, ""}) |> Enum.into(%{}),
            "transaction" => Enum.map(@transaction_fields, &{&1, ""}) |> Enum.into(%{})
          })
      end

    subject_scope = if condition_name == "inherit", do: "next", else: "transaction"

    conditions =
      InterpreterUtils.inject_bindings_and_functions(conditions,
        bindings: bindings,
        subject: subject_scope
      )

    Map.put(
      previous_conditions,
      String.to_existing_atom(condition_name),
      aggregate_conditions(conditions, subject_scope)
    )
  end

  defp aggregate_conditions(conditions, subject_scope) do
    Enum.reduce(conditions, %Conditions{}, fn {subject, condition}, acc ->
      condition = do_aggregate_condition(condition, subject_scope, subject)
      Map.put(acc, String.to_existing_atom(subject), condition)
    end)
  end

  defp do_aggregate_condition(condition, _, "origin_family"),
    do: String.to_existing_atom(condition)

  defp do_aggregate_condition(condition, subject_scope, subject)
       when is_binary(condition) or is_number(condition) do
    {:==, [],
     [
       {:get_in, [], [{:scope, [], nil}, [subject_scope, subject]]},
       condition
     ]}
  end

  defp do_aggregate_condition(condition, subject_scope, subject) when is_list(condition) do
    {:==, [],
     [
       {:get_in, [],
        [
          {:scope, [], nil},
          [subject_scope, subject]
        ]},
       condition
     ]}
  end

  defp do_aggregate_condition(condition, subject_scope, subject) do
    Macro.postwalk(condition, &to_boolean_expression(&1, subject_scope, subject))
  end

  defp to_boolean_expression(
         {{:., metadata, [{:__aliases__, _, [:Library]}, fun]}, _, args},
         subject_scope,
         subject
       ) do
    arguments =
      if :erlang.function_exported(Library, fun, length(args)) do
        # If the number of arguments fullfill the function's arity  (without subject)
        args
      else
        [
          {:get_in, metadata, [{:scope, metadata, nil}, [subject_scope, subject]]} | args
        ]
      end

    if fun |> Atom.to_string() |> String.ends_with?("?") do
      {:==, metadata,
       [
         true,
         {{:., metadata, [{:__aliases__, [alias: Library], [:Library]}, fun]}, metadata,
          arguments}
       ]}
    else
      {:==, metadata,
       [
         {:get_in, metadata, [{:scope, metadata, nil}, [subject_scope, subject]]},
         {{:., metadata, [{:__aliases__, [alias: Library], [:Library]}, fun]}, metadata,
          arguments}
       ]}
    end
  end

  defp to_boolean_expression(condition = {:%{}, _, _}, subject_scope, subject) do
    {:==, [],
     [
       {:get_in, [], [{:scope, [], nil}, [subject_scope, subject]]},
       condition
     ]}
  end

  # Flatten comparison operations
  defp to_boolean_expression({op, _, [{:==, metadata, [{:get_in, _, _}, comp_a]}, comp_b]}, _, _)
       when op in [:==, :>=, :<=] do
    {op, metadata, [comp_a, comp_b]}
  end

  defp to_boolean_expression(condition, _, _), do: condition
end
