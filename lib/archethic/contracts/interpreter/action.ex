defmodule Archethic.Contracts.ActionInterpreter do
  @moduledoc false

  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.Contracts.Interpreter.TransactionStatements
  alias Archethic.Contracts.Interpreter.Utils, as: InterpreterUtils

  @transaction_fields InterpreterUtils.transaction_fields()

  @library_functions_names Library.__info__(:functions)
                           |> Enum.map(&Atom.to_string(elem(&1, 0)))

  @transaction_statements_functions_names TransactionStatements.__info__(:functions)
                                          |> Enum.map(&Atom.to_string(elem(&1, 0)))

  @type trigger :: :transaction | :interval | :datetime | :oracle

  @doc ~S"""
  Parse an action block

  ## Examples

      iex> ActionInterpreter.parse({{:atom, "actions"}, [line: 1],
      ...> [
      ...>   [
      ...>     {{:atom, "triggered_by"}, {{:atom, "transaction"}, [line: 1], nil}}
      ...>   ],
      ...>   [
      ...>     do: {{:atom, "add_uco_transfer"}, [line: 2],
      ...>      [
      ...>        [
      ...>          {{:atom, "to"}, "0000D574D171A484F8DEAC2D61FC3F7CC984BEB52465D69B3B5F670090742CBF5CC"},
      ...>          {{:atom, "amount"}, 2000000000}
      ...>        ]
      ...>      ]}
      ...>   ]
      ...> ]})
      {:ok, :transaction, {:=, [line: 2], [{:scope, [line: 2], nil}, {:update_in, [line: 2], [{:scope, [line: 2], nil}, ["next_transaction"], {:&, [line: 2], [{{:., [line: 2], [{:__aliases__, [alias: Archethic.Contracts.Interpreter.TransactionStatements], [:TransactionStatements]}, :add_uco_transfer]}, [line: 2], [{:&, [line: 2], [1]}, [{"to", "0000D574D171A484F8DEAC2D61FC3F7CC984BEB52465D69B3B5F670090742CBF5CC"}, {"amount", 2000000000}]]}]}]}]}}

      # Usage with trigger accepting parameters
      
      iex> ActionInterpreter.parse({{:atom, "actions"}, [line: 1],
      ...> [
      ...>   [
      ...>     {{:atom, "triggered_by"}, {{:atom, "datetime"},
      ...>      [line: 1], nil}},
      ...>     {{:atom, "at"}, 1391309030}
      ...>   ],
      ...>   [
      ...>     do: {{:atom, "add_recipient"}, [line: 2],
      ...>      ["0000D574D171A484F8DEAC2D61FC3F7CC984BEB52465D69B3B5F670090742CBF5CC"]}
      ...>   ]
      ...> ]})
      {:ok, {:datetime, ~U[2014-02-02 02:43:50Z]}, {:=, [line: 2], [{:scope, [line: 2], nil}, {:update_in, [line: 2], [{:scope, [line: 2], nil}, ["next_transaction"], {:&, [line: 2], [{{:., [line: 2], [{:__aliases__, [alias: Archethic.Contracts.Interpreter.TransactionStatements], [:TransactionStatements]}, :add_recipient]}, [line: 2], [{:&, [line: 2], [1]}, "0000D574D171A484F8DEAC2D61FC3F7CC984BEB52465D69B3B5F670090742CBF5CC"]}]}]}]}}
  """
  @spec parse(Macro.t()) :: {:ok, trigger(), Macro.t()}
  def parse(ast) do
    try do
      {_node, {:ok, trigger, actions}} =
        Macro.traverse(
          ast,
          {:ok, %{scope: :root}},
          &prewalk(&1, &2),
          &postwalk/2
        )

      {:ok, trigger, actions}
    catch
      {:error, reason, {{:atom, key}, metadata, _}} ->
        {:error, InterpreterUtils.format_error_reason({metadata, reason, key})}

      {:error, node = {{:atom, key}, metadata, _}} ->
        IO.inspect(node)
        {:error, InterpreterUtils.format_error_reason({metadata, "unexpected term", key})}
    end
  end

  # Whitelist the actions DSL
  defp prewalk(node = {{:atom, "actions"}, _, _}, {:ok, context = %{scope: :root}}) do
    {node, {:ok, %{context | scope: :actions}}}
  end

  # Whitelist the triggers
  defp prewalk(
         node = {{:atom, "triggered_by"}, {{:atom, trigger}, _, _}},
         {:ok, context = %{scope: :actions}}
       )
       when trigger in ["transaction", "datetime", "interval", "oracle"] do
    {node, {:ok, %{context | scope: {:actions, String.to_existing_atom(trigger)}}}}
  end

  defp prewalk(node = {{:atom, "at"}, timestamp}, acc = {:ok, %{scope: {:actions, :datetime}}}) do
    with digits when length(digits) == 10 <- Integer.digits(timestamp),
         {:ok, _} <- DateTime.from_unix(timestamp) do
      {node, acc}
    else
      _ ->
        {node, {:error, "invalid datetime"}}
    end
  end

  # Whitelist the transaction statements functions
  defp prewalk(
         node = {{:atom, function}, _, _},
         {:ok, context = %{scope: parent_scope = {:actions, _}}}
       )
       when function in @transaction_statements_functions_names do
    {node, {:ok, %{context | scope: {:function, function, parent_scope}}}}
  end

  # Whitelist the add_uco_transfer function parameters
  defp prewalk(
         node = {{:atom, "to"}, address},
         acc = {:ok, %{scope: {"add_uco_transfer", {:actions, _}}}}
       )
       when is_binary(address) do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "to"}, address},
         acc = {:ok, %{scope: {:function, "add_uco_transfer", {:actions, _}}}}
       )
       when is_binary(address) do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "to"}, {{:atom, _}, _, _}},
         acc = {:ok, %{scope: {:function, "add_uco_transfer", {:actions, _}}}}
       ) do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "amount"}, amount},
         acc = {:ok, %{scope: {:function, "add_uco_transfer", {:actions, _}}}}
       )
       when is_integer(amount) and amount > 0 do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "amount"}, {{:atom, _}, _, _}},
         acc = {:ok, %{scope: {:function, "add_uco_transfer", {:actions, _}}}}
       ) do
    {node, acc}
  end

  # Whitelist the add_token_transfer argument list
  defp prewalk(
         node = {{:atom, "to"}, address},
         acc = {:ok, %{scope: {:function, "add_token_transfer", {:actions, _}}}}
       )
       when is_binary(address) do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "to"}, {{:atom, _}, _, _}},
         acc = {:ok, %{scope: {:function, "add_token_transfer", {:actions, _}}}}
       ) do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "amount"}, amount},
         acc = {:ok, %{scope: {:function, "add_token_transfer", {:actions, _}}}}
       )
       when is_integer(amount) and amount > 0 do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "amount"}, {{:atom, _}, _, _}},
         acc = {:ok, %{scope: {:function, "add_token_transfer", {:actions, _}}}}
       ) do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "token_address"}, token_address},
         acc = {:ok, %{scope: {:function, "add_token_transfer", {:actions, _}}}}
       )
       when is_binary(token_address) do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "token_address"}, {{:atom, _}, _, _}},
         acc = {:ok, %{scope: {:function, "add_token_transfer", {:actions, _}}}}
       ) do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "token_id"}, token_id},
         acc = {:ok, %{scope: {:function, "add_token_transfer", {:actions, _}}}}
       )
       when is_integer(token_id) and token_id >= 0 do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "token_id"}, {{:atom, _}, _, _}},
         acc = {:ok, %{scope: {:function, "add_token_transfer", {:actions, _}}}}
       ) do
    {node, acc}
  end

  # Whitelist the add_ownership argument list
  defp prewalk(
         node = {{:atom, "secret"}, secret},
         acc = {:ok, %{scope: {:function, "add_ownership", {:actions, _}}}}
       )
       when is_binary(secret) do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "secret"}, {{:atom, _}, _, _}},
         acc = {:ok, %{scope: {:function, "add_ownership", {:actions, _}}}}
       ) do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "secret_key"}, {{:atom, _}, _, _}},
         acc = {:ok, %{scope: {:function, "add_ownership", {:actions, _}}}}
       ) do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "authorized_public_keys"}, authorized_public_keys},
         acc = {:ok, %{scope: {:function, "add_ownership", {:actions, _}}}}
       )
       when is_list(authorized_public_keys) do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "authorized_public_keys"}, {{:atom, _, _}}},
         acc = {:ok, %{scope: {:function, "add_ownership", {:actions, _}}}}
       ) do
    {node, acc}
  end

  defp prewalk(node, {:error, reason}) do
    throw({:error, reason, node})
  end

  defp prewalk(node, acc) do
    InterpreterUtils.prewalk(node, acc)
  end

  defp postwalk(
         node =
           {{:atom, "actions"}, [line: _],
            [[{{:atom, "triggered_by"}, {{:atom, trigger_type}, _, _}} | opts], [do: actions]]},
         {:ok, _}
       ) do
    actions =
      InterpreterUtils.inject_bindings_and_functions(actions,
        bindings: %{
          "contract" => Enum.map(@transaction_fields, &{&1, ""}) |> Enum.into(%{}),
          "transaction" => Enum.map(@transaction_fields, &{&1, ""}) |> Enum.into(%{})
        }
      )

    case trigger_type do
      "transaction" ->
        {node, {:ok, :transaction, actions}}

      "datetime" ->
        [{{:atom, "at"}, timestamp}] = opts
        datetime = DateTime.from_unix!(timestamp)
        {node, {:ok, {:datetime, datetime}, actions}}

      "interval" ->
        [{{:atom, "at"}, interval}] = opts
        {node, {:ok, {:interval, interval}, actions}}

      "oracle" ->
        {node, {:ok, :oracle, actions}}
    end
  end

  defp postwalk(node, acc) do
    InterpreterUtils.postwalk(node, acc)
  end
end
