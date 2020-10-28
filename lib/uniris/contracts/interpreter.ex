defmodule Uniris.Contracts.Interpreter do
  @moduledoc false

  alias Crontab.CronExpression.Parser, as: CronParser

  alias Uniris.Contracts.Contract
  alias Uniris.SharedSecrets

  @transaction_fields_whitelist [
    :address,
    :previous_signature,
    :previous_public_key,
    :origin_signature,
    :content,
    :keys,
    :uco_ledger
  ]

  @transaction_functions [:new_transaction]
  @string_functions [:regex]

  @conditions_functions @string_functions
  @actions_functions @transaction_functions ++ @string_functions

  @type parsing_error ::
          :unexpected_token
          | :invalid_datetime
          | :invalid_interval
          | :invalid_origin_family
          | :invalid_post_paid_address

  @doc """
  Parse a smart contract code and return the filtered AST representation.

  The parser uses a whitelist of instructions, the rest will be rejected

  ## Examples

      iex> Interpreter.parse("
      ...>    trigger datetime: 1603270603
      ...>    actions do end
      ...> ")
      {
        :ok,
        {
          :__block__,
          [],
          [
            {:trigger, [line: 1], [[datetime: 1603270603]]},
            {:actions, [line: 2], [[do: {:__block__, [], []}]]}
          ]
        }
      }

      iex> Interpreter.parse("
      ...>    trigger datetime: 0000000
      ...>    actions do
      ...>    end
      ...> ")
      {:error, :invalid_datetime}

      iex> Interpreter.parse("
      ...>    actions do
      ...>       System.user_home
      ...>    end
      ...> ")
      {:error, :unexpected_token}

  """
  @spec parse(code :: binary()) :: {:ok, term()} | {:error, parsing_error()}
  def parse(code) when is_binary(code) do
    with code <- String.trim(code),
         {:ok, ast} <- Code.string_to_quoted(code),
         {filter_ast, {:ok, _}} <- Macro.prewalk(ast, {:ok, :root}, &filter_ast/2) do
      {:ok, filter_ast}
    else
      {:error, reason} ->
        {:error, reason}

      {_node, {:error, reason}} ->
        {:error, reason}
    end
  end

  # Whitelist the actions
  defp filter_ast(node = {:actions, _, [[do: _]]}, {:ok, :root}) do
    {node, {:ok, :actions}}
  end

  # Whitelist the multiline in the actions
  defp filter_ast(node = {:__block__, _, _}, acc = {:ok, scope})
       when scope in [:actions, :root] do
    {node, acc}
  end

  # Whitelist the trigger 'datetime' by checking the datetime number and if the timestamp is greater than now
  defp filter_ast(node = {:trigger, _, [[datetime: datetime]]}, acc = {:ok, :root})
       when is_number(datetime) do
    if length(Integer.digits(datetime)) != 10 do
      {node, {:error, :invalid_datetime}}
    else
      case DateTime.from_unix(datetime) do
        {:ok, time} ->
          if time.year >= 2019 and DateTime.diff(time, DateTime.utc_now()) < 0 do
            {node, acc}
          else
            {node, {:error, :invalid_datetime}}
          end

        _ ->
          {node, {:error, :invalid_datetime}}
      end
    end
  end

  # Whitelist the trigger 'interval' by checking the time interval (CronTab like)
  defp filter_ast(node = {:trigger, _, [[interval: interval]]}, acc = {:ok, :root})
       when is_binary(interval) do
    case CronParser.parse(interval) do
      {:ok, _} ->
        {node, acc}

      _ ->
        {node, {:error, :invalid_interval}}
    end
  end

  # Whitelist the condition 'origin_family' by checking its support
  defp filter_ast(
         node = {:condition, _, [[origin_family: {family, _, nil}]]},
         acc = {:ok, :root}
       ) do
    if family in SharedSecrets.list_origin_families() do
      {node, acc}
    else
      {node, {:error, :invalid_origin_family}}
    end
  end

  # Whitelist the condition 'post_paid_fee', if the address is a string must be valid hash
  # TODO: size of the hash can change according of the new hash algorithm could be dynamic assigned
  defp filter_ast(node = {:condition, _, [[post_paid_fee: address]]}, acc = {:ok, :root}) do
    cond do
      is_binary(address) and String.match?(address, ~r/^[A-Fa-f0-9]{64}$/) ->
        {node, acc}

      match?({:@, _, [{_, _, nil}]}, address) ->
        {node, acc}

      true ->
        {node, {:error, :invalid_post_paid_address}}
    end
  end

  # Whitelist the condition: 'response'
  defp filter_ast(node = {:condition, _, [[response: _]]}, {:ok, _}) do
    {node, {:ok, :condition}}
  end

  # Whitelist the condition: 'inherit'
  defp filter_ast(node = {:condition, _, [[inherit: _]]}, {:ok, _}), do: {node, {:ok, :condition}}

  # Continue the scoping as condition to whitelist only some behaviors
  defp filter_ast(node, {:ok, :condition}), do: {node, {:ok, :condition}}

  defp filter_ast(node = {:+, _, _}, acc = {:ok, scope}) when scope in [:actions],
    do: {node, acc}

  defp filter_ast(node = {:-, _, _}, acc = {:ok, scope}) when scope in [:actions],
    do: {node, acc}

  defp filter_ast(node = {:/, _, _}, acc = {:ok, scope}) when scope in [:actions],
    do: {node, acc}

  defp filter_ast(node = {:*, _, _}, acc = {:ok, scope}) when scope in [:actions],
    do: {node, acc}

  defp filter_ast(node = {:>, _, _}, acc = {:ok, scope}) when scope in [:actions, :condition],
    do: {node, acc}

  defp filter_ast(node = {:<, _, _}, acc = {:ok, scope}) when scope in [:actions, :condition],
    do: {node, acc}

  defp filter_ast(node = {:>=, _, _}, acc = {:ok, scope}) when scope in [:actions, :condition],
    do: {node, acc}

  defp filter_ast(node = {:<=, _, _}, acc = {:ok, scope}) when scope in [:actions, :condition],
    do: {node, acc}

  defp filter_ast(true, acc = {:ok, _}), do: {true, acc}
  defp filter_ast(false, acc = {:ok, _}), do: {false, acc}
  defp filter_ast(number, acc = {:ok, _}) when is_number(number), do: {number, acc}
  defp filter_ast(string, acc = {:ok, _}) when is_binary(string), do: {string, acc}
  defp filter_ast(node = node, acc = {:ok, _}) when is_list(node), do: {node, acc}
  defp filter_ast(node = {:do, _}, acc = {:ok, _}), do: {node, acc}
  defp filter_ast(key, acc = {:ok, _}) when is_atom(key), do: {key, acc}
  defp filter_ast({key, _} = node, acc = {:ok, _}) when is_atom(key), do: {node, acc}

  # Allow variable assignation inside the actions
  defp filter_ast(node = {:=, _, _}, acc = {:ok, scope}) when scope in [:actions],
    do: {node, acc}

  # Whitelist the use of member fields for globals
  defp filter_ast(
         node = {{:., _, [{:@, _, _}, _]}, _, []},
         acc = {:ok, _parent}
       ),
       do: {node, acc}

  # Whitelist the use of response member fields
  defp filter_ast(
         node = {{:., _, [{:response, _, _}, field]}, _, []},
         acc = {:ok, _}
       )
       when field in @transaction_fields_whitelist do
    {node, acc}
  end

  # Whitelist the definition of globals in the root
  defp filter_ast(node = {:@, _, [{key, _, [val]}]}, acc = {:ok, :root})
       when is_atom(key) and not is_nil(val),
       do: {node, acc}

  # Whitelist the use of globals in triggers, conditions and action
  defp filter_ast(node = {:@, _, [{key, _, nil}]}, acc = {:ok, scope})
       when is_atom(key) and scope in [:actions, :condition, :trigger],
       do: {node, acc}

  # Whitelist the use of atoms in the root when used as global names
  defp filter_ast(node = {key, _, [_]}, acc = {:ok, :root})
       when is_atom(key) and key not in [:condition, :actions, :trigger] do
    {node, acc}
  end

  defp filter_ast(node = {:if, _, [_, [do: _]]}, acc = {:ok, :actions}), do: {node, acc}
  defp filter_ast(node = {:if, _, [_, [do: _, else: _]]}, acc = {:ok, :actions}), do: {node, acc}
  defp filter_ast(node = [do: _, else: _], acc = {:ok, :actions}), do: {node, acc}

  # Whitelist the used of functions in the conditions
  defp filter_ast(node = {key, _, args}, {:ok, :conditions} = acc)
       when is_atom(key) and is_list(args) and key in @conditions_functions do
    {node, acc}
  end

  # Whitelist the used of functions in the actions
  defp filter_ast(node = {key, _, args}, acc = {:ok, :actions})
       when is_atom(key) and is_list(args) and key in @actions_functions do
    {node, acc}
  end

  # Whitelist the used of variables in the actions
  defp filter_ast(node = {var, _, nil}, acc = {:ok, scope})
       when is_atom(var)
       when scope in [:actions],
       do: {node, acc}

  # Whitelist the in operation
  defp filter_ast(node = {:in, _, [_, _]}, acc = {:ok, _}), do: {node, acc}

  # Blacklist anything else
  defp filter_ast(node, {:ok, _scope}) do
    {node, {:error, :unexpected_token}}
  end

  defp filter_ast(node, e = {:error, _}), do: {node, e}

  @doc """
  Execute the contract actions and respecting its conditions
  """
  @spec execute(Contract.t()) :: {:ok, any()} | {:error, :condition_not_respected}
  def execute(%Contract{actions: actions, conditions: %{response: nil}, constants: constants}) do
    context = Map.to_list(constants)
    {output, _} = Code.eval_quoted(actions, context)
    process_output(output)
  end

  def execute(%Contract{
        actions: actions,
        conditions: %{response: resp_condition},
        constants: constants
      }) do
    context = Map.to_list(constants)

    if Code.eval_quoted(resp_condition, context) do
      {output, _} = Code.eval_quoted(actions, context)
      process_output(output)
    else
      {:error, :condition_not_respected}
    end
  end

  defp process_output(_) do
    :ok
  end
end
