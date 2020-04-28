defmodule UnirisCore.Interpreter.AST do
  @moduledoc false

  @origin_families [:biometric, :software]

  @transaction_fields_whitelist [
    :address,
    :signature,
    :previous_public_key,
    :origin_signature,
    :content,
    :keys,
    :uco_ledger
  ]

  @transaction_functions [:new_transaction]
  @string_functions [:regex]

  @conditions_functions [] ++ @string_functions
  @actions_functions [] ++ @transaction_functions ++ @string_functions

  @spec parse(code :: binary()) :: {:ok, term()} | {:error, :syntax} | {:error, {:syntax, atom()}}
  def parse(code) when is_binary(code) do
    with code <- String.trim(code),
         {:ok, ast} <- Code.string_to_quoted(code),
         {filter_ast, {:ok, _}} <- Macro.prewalk(ast, {:ok, :root}, &filter_ast/2) do
      {:ok, filter_ast}
    else
      {:error, _} ->
        {:error, {:invalid_syntax, :unexpected_token}}

      {_node, {:error, reason}} ->
        {:error, {:invalid_syntax, reason}}
    end
  end

  ## Whitelist the actions
  defp filter_ast({:actions, _, [[do: _]]} = node, {:ok, :root}) do
    {node, {:ok, :actions}}
  end

  ## Whitelist the multiline in the actions
  defp filter_ast({:__block__, _, _} = node, {:ok, scope} = acc)
       when scope in [:actions, :root] do
    {node, acc}
  end

  ## Whitelist the trigger 'datetime' by checking the datetime number and if the timestamp is greater than now
  defp filter_ast({:trigger, _, [[datetime: datetime]]} = node, {:ok, :root} = acc)
       when is_number(datetime) do
    if length(Integer.digits(datetime)) != 10 do
      {node, {:error, :invalid_timestamp}}
    else
      case DateTime.from_unix(datetime) do
        {:ok, time} ->
          if time.year >= 2019 and DateTime.diff(time, DateTime.utc_now()) < 0 do
            {node, acc}
          else
            {node, {:error, :invalid_timestamp}}
          end

        _ ->
          {node, {:error, :invalid_timestamp}}
      end
    end
  end

  ## Whitelist the trigger 'interval' by checking the time interval (seconds)
  defp filter_ast({:trigger, _, [[interval: interval]]} = node, {:ok, :root} = acc)
       when is_integer(interval) and interval > 0 do
    {node, acc}
  end

  ## Whitelist the condition 'origin_family' by checking its support
  defp filter_ast(
         {:condition, _, [[origin_family: {:@, _, [{family, _, nil}]}]]} = node,
         {:ok, :root} = acc
       )
       when family in @origin_families do
    {node, acc}
  end

  ## Whitelist the condition 'post_paid_fee', if the address is a string must be valid hash
  ## TODO: size of the hash can change according of the new hash algorithm could be dynamic assigned
  defp filter_ast({:condition, _, [[post_paid_fee: address]]} = node, {:ok, :root} = acc) do
    cond do
      is_binary(address) and String.match?(address, ~r/^[A-Fa-f0-9]{64}$/) ->
        {node, acc}

      match?({:@, _, [{_, _, nil}]}, address) ->
        {node, acc}

      true ->
        {node, {:error, :invalid_post_paid_address}}
    end
  end

  # ## Whitelist the condition: 'response'
  defp filter_ast({:condition, _, [[response: _]]} = node, {:ok, _}) do
    {node, {:ok, :condition}}
  end

  # ## Whitelist the condition: 'inherit'
  defp filter_ast({:condition, _, [[inherit: _]]} = node, {:ok, _}), do: {node, {:ok, :condition}}

  # # Continue the scoping as condition to whitelist only some behaviors
  defp filter_ast(node, {:ok, :condition}), do: {node, {:ok, :condition}}

  defp filter_ast({:+, _, _} = node, {:ok, scope} = acc) when scope in [:actions],
    do: {node, acc}

  defp filter_ast({:-, _, _} = node, {:ok, scope} = acc) when scope in [:actions],
    do: {node, acc}

  defp filter_ast({:/, _, _} = node, {:ok, scope} = acc) when scope in [:actions],
    do: {node, acc}

  defp filter_ast({:*, _, _} = node, {:ok, scope} = acc) when scope in [:actions],
    do: {node, acc}

  defp filter_ast({:>, _, _} = node, {:ok, scope} = acc) when scope in [:actions, :condition],
    do: {node, acc}

  defp filter_ast({:<, _, _} = node, {:ok, scope} = acc) when scope in [:actions, :condition],
    do: {node, acc}

  defp filter_ast({:>=, _, _} = node, {:ok, scope} = acc) when scope in [:actions, :condition],
    do: {node, acc}

  defp filter_ast({:<=, _, _} = node, {:ok, scope} = acc) when scope in [:actions, :condition],
    do: {node, acc}

  defp filter_ast(true, {:ok, _} = acc), do: {true, acc}
  defp filter_ast(false, {:ok, _} = acc), do: {false, acc}
  defp filter_ast(number, {:ok, _} = acc) when is_number(number), do: {number, acc}
  defp filter_ast(string, {:ok, _} = acc) when is_binary(string), do: {string, acc}
  defp filter_ast(node = node, {:ok, _} = acc) when is_list(node), do: {node, acc}
  defp filter_ast({:do, _} = node, {:ok, _} = acc), do: {node, acc}
  defp filter_ast(key, {:ok, _} = acc) when is_atom(key), do: {key, acc}
  defp filter_ast({key, _} = node, {:ok, _} = acc) when is_atom(key), do: {node, acc}

  ## Allow variable assignation inside the actions
  defp filter_ast({:=, _, _} = node, {:ok, scope} = acc) when scope in [:actions],
    do: {node, acc}

  ## Whitelist the use of member fields for globals
  defp filter_ast(
         {{:., _, [{:@, _, _}, _]}, _, []} = node,
         {:ok, _parent} = acc
       ),
       do: {node, acc}

  # Whitelist the use of reponse member fields
  defp filter_ast(
         {{:., _, [{:response, _, _}, field]}, _, []} = node,
         {:ok, _} = acc
       )
       when field in @transaction_fields_whitelist do
    {node, acc}
  end

  ## Whitelist the definition of globals in the root
  defp filter_ast({:@, _, [{key, _, [val]}]} = node, {:ok, :root} = acc)
       when is_atom(key) and not is_nil(val),
       do: {node, acc}

  ## Whitelist the use of globals in triggers, conditions and action
  defp filter_ast({:@, _, [{key, _, nil}]} = node, {:ok, scope} = acc)
       when is_atom(key) and scope in [:actions, :condition, :trigger],
       do: {node, acc}

  ## Whitelist the use of atoms in the root when used as global names
  defp filter_ast({key, _, [_]} = node, {:ok, :root} = acc)
       when is_atom(key) and key not in [:condition, :actions, :trigger] do
    {node, acc}
  end

  defp filter_ast({:if, _, [_, [do: _]]} = node, {:ok, :actions} = acc), do: {node, acc}
  defp filter_ast({:if, _, [_, [do: _, else: _]]} = node, {:ok, :actions} = acc), do: {node, acc}
  defp filter_ast([do: _, else: _] = node, {:ok, :actions} = acc), do: {node, acc}

  # Whitelist the used of functions in the conditions
  defp filter_ast({key, _, args} = node, {:ok, :conditions} = acc)
       when is_atom(key) and is_list(args) and key in @conditions_functions do
    {node, acc}
  end

  ## Whitelist the used of functions in the actions
  defp filter_ast({key, _, args} = node, {:ok, :actions} = acc)
       when is_atom(key) and is_list(args) and key in @actions_functions do
    {node, acc}
  end

  ## Whitelist the used of variables in the actions
  defp filter_ast({var, _, nil} = node, {:ok, scope} = acc)
       when is_atom(var)
       when scope in [:actions],
       do: {node, acc}

  ## Whitelist the in operation
  defp filter_ast({:in, _, [_, _]} = node, {:ok, _} = acc), do: {node, acc}

  ## Blaclikst anything else
  defp filter_ast(node, {:ok, _scope}) do
    {node, {:error, :unexpected_token}}
  end

  defp filter_ast(node, {:error, _} = e), do: {node, e}
end
