defmodule Archethic.Contracts.Interpreter.Legacy.ConditionInterpreter do
  @moduledoc false

  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.Conditions.Subjects, as: ConditionsSubjects
  alias Archethic.Contracts.Interpreter.Legacy.Library
  alias Archethic.Contracts.Interpreter.Legacy.UtilsInterpreter

  alias Archethic.SharedSecrets

  @condition_fields ConditionsSubjects.__struct__()
                    |> Map.keys()
                    |> Enum.reject(&(&1 == :__struct__))
                    |> Enum.map(&Atom.to_string/1)

  @transaction_fields UtilsInterpreter.transaction_fields()

  @exported_library_functions Library.__info__(:functions)

  @type condition_type :: {:transaction, nil, nil} | :inherit | :oracle

  require Logger

  @doc ~S"""
  Parse a condition block and returns the right condition's type with a `Archethic.Contracts.Contract.Conditions` struct

  ## Examples

      iex> ConditionInterpreter.parse(
      ...>   {{:atom, "condition"}, [line: 1],
      ...>    [
      ...>      [
      ...>        {{:atom, "transaction"},
      ...>         [
      ...>           {{:atom, "content"}, "hello"}
      ...>         ]}
      ...>      ]
      ...>    ]}
      ...> )
      {:ok, {:transaction, nil, nil},
       %ConditionsSubjects{
         content:
           {:==, [],
            [
              {:get_in, [],
               [
                 {:scope, [], nil},
                 ["transaction", "content"]
               ]},
              "hello"
            ]}
       }}

    Usage of functions in the condition fields

      iex> ConditionInterpreter.parse(
      ...>   {{:atom, "condition"}, [line: 1],
      ...>    [
      ...>      [
      ...>        {{:atom, "transaction"},
      ...>         [
      ...>           {{:atom, "content"},
      ...>            {{:atom, "hash"}, [line: 2],
      ...>             [
      ...>               {{:., [line: 2],
      ...>                 [
      ...>                   {{:atom, "contract"}, [line: 2], nil},
      ...>                   {:atom, "code"}
      ...>                 ]}, [no_parens: true, line: 2], []}
      ...>             ]}}
      ...>         ]}
      ...>      ]
      ...>    ]}
      ...> )
      {
        :ok,
        {:transaction, nil, nil},
        %ConditionsSubjects{
          content:
            {:==, [line: 2],
             [
               {:get_in, [line: 2],
                [
                  {:scope, [line: 2], nil},
                  ["transaction", "content"]
                ]},
               {
                 {:., [line: 2],
                  [
                    {:__aliases__, [alias: Archethic.Contracts.Interpreter.Legacy.Library],
                     [:Library]},
                    :hash
                  ]},
                 [line: 2],
                 [
                   {:get_in, [line: 2],
                    [
                      {:scope, [line: 2], nil},
                      ["contract", "code"]
                    ]}
                 ]
               }
             ]}
        }
      }

    Usage with multiple condition fields

      iex> ConditionInterpreter.parse(
      ...>   {{:atom, "condition"}, [line: 1],
      ...>    [
      ...>      {{:atom, "transaction"},
      ...>       [
      ...>         {{:atom, "content"}, "hello"},
      ...>         {{:atom, "uco_transfers"},
      ...>          {:%{}, [line: 3],
      ...>           [
      ...>             {"00006B368BE45DACD0CBC0EC5893BDC1079448181AA88A2CBB84AF939912E858843E",
      ...>              1_000_000_000}
      ...>           ]}}
      ...>       ]}
      ...>    ]}
      ...> )
      {:ok, {:transaction, nil, nil},
       %ConditionsSubjects{
         content:
           {:==, [], [{:get_in, [], [{:scope, [], nil}, ["transaction", "content"]]}, "hello"]},
         uco_transfers:
           {:==, [],
            [
              {:get_in, [], [{:scope, [], nil}, ["transaction", "uco_transfers"]]},
              {:%{}, [line: 3],
               [
                 {
                   "00006B368BE45DACD0CBC0EC5893BDC1079448181AA88A2CBB84AF939912E858843E",
                   1_000_000_000
                 }
               ]}
            ]}
       }}

    Usage with origin_family condition

      iex> ConditionInterpreter.parse(
      ...>   {{:atom, "condition"}, [line: 1],
      ...>    [
      ...>      [
      ...>        {{:atom, "inherit"},
      ...>         [
      ...>           {{:atom, "origin_family"}, {{:atom, "abc"}, [line: 2], nil}}
      ...>         ]}
      ...>      ]
      ...>    ]}
      ...> )
      {:error, "invalid origin family - L2"}

  """
  @spec parse(any()) ::
          {:ok, condition_type(), ConditionsSubjects.t()} | {:error, reason :: String.t()}
  def parse(ast) do
    case Macro.traverse(
           ast,
           {:ok, %{scope: :root}},
           &prewalk(&1, &2),
           &postwalk/2
         ) do
      {_node, {:ok, condition_name, conditions}} ->
        {:ok, condition_name, conditions}

      {node, _} ->
        {:error, Interpreter.format_error_reason(node, "unexpected term")}
    end
  catch
    {:error, node} ->
      {:error, Interpreter.format_error_reason(node, "unexpected term")}

    {:error, reason, node} ->
      {:error, Interpreter.format_error_reason(node, reason)}
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

  # Whitelist the origin family
  defp prewalk(node = [{{:atom, "origin_family"}, {{:atom, family}, _, _}}], acc = {:ok, _}) do
    families = SharedSecrets.list_origin_families() |> Enum.map(&Atom.to_string/1)

    if family in families do
      {node, acc}
    else
      {node, {:error, "invalid origin family"}}
    end
  end

  defp prewalk(node = [{{:atom, "uco_transfers"}, value}], acc = {:ok, _}) do
    case value do
      {:%{}, _, _} ->
        {node, acc}

      {op, _, _} when op in [:==, :<, :>, :<=, :>=, :if] ->
        {node, acc}

      _ ->
        {node, {:error, "must be a map or a code instruction starting by an comparator"}}
    end
  end

  defp prewalk(node = [{{:atom, "token_transfers"}, value}], acc = {:ok, _}) do
    case value do
      {:%{}, _, _} ->
        {node, acc}

      {op, _, _} when op in [:==, :<, :>, :<=, :>=, :if] ->
        {node, acc}

      _ ->
        {node, {:error, "must be a map or a code instruction starting by an comparator"}}
    end
  end

  # Whitelist the regex_match?/1 function in the condition
  defp prewalk(
         node = {{:atom, "regex_match?"}, _, [_search]},
         acc = {:ok, %{scope: {:condition, _, _}}}
       ) do
    {node, acc}
  end

  # Whitelist the json_path_extract/1 function in the condition
  defp prewalk(
         node = {{:atom, "json_path_extract"}, _, [_search]},
         acc = {:ok, %{scope: {:condition, _, _}}}
       ) do
    {node, acc}
  end

  # Whitelist the json_path_match?/1 function in the condition
  defp prewalk(
         node = {{:atom, "json_path_match?"}, _, [_search]},
         acc = {:ok, %{scope: {:condition, _, _}}}
       ) do
    {node, acc}
  end

  # Whitelist the hash/0 function in the condition
  defp prewalk(
         node = {{:atom, "hash"}, _, []},
         acc = {:ok, %{scope: {:condition, _, _}}}
       ) do
    {node, acc}
  end

  # Whitelist the in?/1 function in the condition
  defp prewalk(
         node = {{:atom, "in?"}, _, [_data]},
         acc = {:ok, %{scope: {:condition, _, _}}}
       ) do
    {node, acc}
  end

  # Whitelist the size/0 function in the condition
  defp prewalk(node = {{:atom, "size"}, _, []}, acc = {:ok, %{scope: {:condition, _, _}}}),
    do: {node, acc}

  # Whitelist the get_genesis_address/0 function in condition
  defp prewalk(
         node = {{:atom, "get_genesis_address"}, _, []},
         acc = {:ok, %{scope: {:condition, _, _}}}
       ) do
    {node, acc}
  end

  # Whitelist the get_first_transaction_address/0 function in condition
  defp prewalk(
         node = {{:atom, "get_first_transaction_address"}, _, []},
         acc = {:ok, %{scope: {:condition, _, _}}}
       ) do
    {node, acc}
  end

  # Whitelist the get_genesis_public_key/0 function in condition
  defp prewalk(
         node = {{:atom, "get_genesis_public_key"}, _, []},
         acc = {:ok, %{scope: {:condition, _, _}}}
       ) do
    {node, acc}
  end

  # Whitelist usage of taps in the field of a condition
  defp prewalk(node = {{:atom, _key}, _val}, acc = {:ok, %{scope: {:condition, _, _}}}) do
    {node, acc}
  end

  defp prewalk(node, {:error, reason}) do
    throw({:error, reason, node})
  end

  defp prewalk(node, acc) do
    UtilsInterpreter.prewalk(node, acc)
  end

  defp postwalk(node, :error), do: {node, :error}

  defp postwalk(
         node = {{:atom, "condition"}, _, [[{{:atom, condition_name}, conditions}]]},
         {:ok, _}
       ) do
    conditions = build_conditions(condition_name, conditions)

    acc =
      case condition_name do
        "transaction" -> {:ok, {:transaction, nil, nil}, conditions}
        "inherit" -> {:ok, :inherit, conditions}
        "oracle" -> {:ok, :oracle, conditions}
      end

    {node, acc}
  end

  defp postwalk(
         node = {{:atom, "condition"}, _, [{{:atom, condition_name}, conditions}]},
         {:ok, _}
       ) do
    conditions = build_conditions(condition_name, conditions)

    acc =
      case condition_name do
        "transaction" -> {:ok, {:transaction, nil, nil}, conditions}
        "inherit" -> {:ok, :inherit, conditions}
        "oracle" -> {:ok, :oracle, conditions}
      end

    {node, acc}
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
         {:ok, _}
       ) do
    conditions = build_conditions(condition_name, conditions)

    acc =
      case condition_name do
        "transaction" -> {:ok, {:transaction, nil, nil}, conditions}
        "inherit" -> {:ok, :inherit, conditions}
        "oracle" -> {:ok, :oracle, conditions}
      end

    {node, acc}
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
    UtilsInterpreter.postwalk(node, acc)
  end

  defp build_conditions(condition_name, conditions) do
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

    conditions
    |> UtilsInterpreter.inject_bindings_and_functions(
      bindings: bindings,
      subject: subject_scope
    )
    |> aggregate_conditions(subject_scope)
  end

  defp aggregate_conditions(conditions, subject_scope) do
    Enum.reduce(conditions, %ConditionsSubjects{}, fn {subject, condition}, acc ->
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
       {:get_in, [], [{:scope, [], nil}, [subject_scope, subject]]},
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
    arg_length = length(args)

    arguments =
      case Keyword.get(@exported_library_functions, fun) do
        ^arg_length ->
          # If the number of arguments fullfill the function's arity  (without subject)
          args

        _ ->
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
       when op in [:==, :>=, :<=, :>, :<] do
    {op, metadata, [comp_a, comp_b]}
  end

  defp to_boolean_expression(condition, _, _), do: condition

  @doc """
  Determines if the conditions of a contract are valid from the given constants
  """
  @spec valid_conditions?(ConditionsSubjects.t(), map()) :: boolean()
  def valid_conditions?(conditions = %ConditionsSubjects{}, constants = %{}) do
    result =
      conditions
      |> Map.from_struct()
      |> Enum.all?(fn {field, condition} ->
        field = Atom.to_string(field)

        case validate_condition({field, condition}, constants) do
          {_, true} ->
            true

          {_, false} ->
            value = get_constant_value(constants, field)

            Logger.debug(
              "Invalid condition for `#{inspect(field)}` with the given value: `#{inspect(value)}` - condition: #{inspect(condition)}"
            )

            false
        end
      end)

    if result do
      result
    else
      result
    end
  end

  defp get_constant_value(constants, field) do
    case get_in(constants, [
           Access.key("transaction", %{}),
           Access.key(field, "")
         ]) do
      "" ->
        get_in(constants, ["next", field])

      value ->
        value
    end
  end

  defp validate_condition({"origin_family", _}, _) do
    # Skip the verification
    # The Proof of Work algorithm will use this condition to verify the transaction
    {"origin_family", true}
  end

  defp validate_condition({"address", nil}, _) do
    # Skip the verification as the address changes for each transaction
    {"address", true}
  end

  defp validate_condition({"previous_public_key", nil}, _) do
    # Skip the verification as the previous public key changes for each transaction
    {"previous_public_key", true}
  end

  defp validate_condition({"timestamp", nil}, _) do
    # Skip the verification as timestamp changes for each transaction
    {"timestamp", true}
  end

  defp validate_condition({"type", nil}, %{"next" => %{"type" => type}})
       when type in ["transfer", "contract"] do
    # Skip the verification when it's the default type
    {"type", true}
  end

  defp validate_condition({"content", nil}, %{"next" => %{"content" => ""}}) do
    # Skip the verification when it's the default type
    {"content", true}
  end

  defp validate_condition({"code", nil}, %{
         "next" => %{"code" => next_code},
         "previous" => %{"code" => prev_code}
       }) do
    quoted_next_code =
      next_code
      |> Code.string_to_quoted!(static_atoms_encoder: &atom_encoder/2)

    quoted_previous_code =
      prev_code
      |> Code.string_to_quoted!(static_atoms_encoder: &atom_encoder/2)

    {"code", quoted_next_code == quoted_previous_code}
  end

  # Validation rules for inherit constraints
  defp validate_condition({field, nil}, %{"previous" => prev, "next" => next}) do
    {field, Map.get(prev, field) == Map.get(next, field)}
  end

  defp validate_condition({field, condition}, constants = %{"next" => next}) do
    result = execute_condition_code(condition, constants)

    if is_boolean(result) do
      {field, result}
    else
      {field, Map.get(next, field) == result}
    end
  end

  # Validation rules for incoming transaction
  defp validate_condition({field, nil}, %{"transaction" => _}) do
    # Skip the validation if no transaction conditions are provided
    {field, true}
  end

  defp validate_condition(
         {field, condition},
         constants = %{"transaction" => transaction}
       ) do
    result = execute_condition_code(condition, constants)

    if is_boolean(result) do
      {field, result}
    else
      {field, Map.get(transaction, field) == result}
    end
  end

  defp execute_condition_code(quoted_code, constants) do
    {res, _} = Code.eval_quoted(quoted_code, scope: constants)
    res
  end

  defp atom_encoder(atom, _) do
    if atom in ["if"] do
      {:ok, String.to_atom(atom)}
    else
      {:ok, {:atom, atom}}
    end
  end
end
