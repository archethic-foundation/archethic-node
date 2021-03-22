defmodule Uniris.Contracts.Interpreter do
  @moduledoc false

  alias Crontab.CronExpression.Parser, as: CronParser

  alias __MODULE__.ActionStatements
  alias __MODULE__.Library
  alias Uniris.Contracts.Contract

  alias Uniris.SharedSecrets

  @transaction_fields [
    :address,
    :type,
    :timestamp,
    :previous_signature,
    :previous_public_key,
    :origin_signature,
    :content,
    :keys,
    :code,
    :uco_ledger,
    :nft_ledger,
    :uco_transferred,
    :nft_transferred,
    :uco_transfers,
    :nft_transfers,
    :authorized_keys,
    :secret,
    :recipients
  ]

  @inherit_fields [
    :code,
    :secret,
    :content,
    :uco_transferred,
    :nft_transferred,
    :uco_transfers,
    :nft_transfers
  ]

  @allowed_transaction_types [:transfer, :nft, :hosting]

  @allowed_atoms [
                   :condition,
                   :origin_family,
                   :inherit,
                   :transaction,
                   :contract,
                   :actions,
                   :triggered_by,
                   :interval,
                   :datetime,
                   :at,
                   :next_transaction,
                   :previous_transaction,
                   :if,
                   :else
                 ] ++
                   ActionStatements.allowed_atoms() ++
                   Library.allowed_atoms() ++
                   @allowed_transaction_types ++
                   @transaction_fields ++
                   SharedSecrets.list_origin_families()

  @doc ~S"""
  Parse a smart contract code and return the filtered AST representation.

  The parser uses a whitelist of instructions, the rest will be rejected

  ## Examples

      iex> Interpreter.parse("
      ...>    condition origin_family: biometric
      ...>
      ...>    condition transaction: regex_match?(content, \"^Mr.Y|Mr.X{1}$\")
      ...>
      ...>    condition inherit,
      ...>       content: regex_match?(\"hello\")
      ...>
      ...>    actions triggered_by: datetime, at: 1603270603 do
      ...>      set_type transfer
      ...>      add_uco_transfer to: \"22368B50D3B2976787CFCC27508A8E8C67483219825F998FC9D6908D54D0FE10\", amount: 10.04
      ...>    end
      ...> ")
      {:ok,
        %Contract{
         conditions: %Conditions{
            inherit: [content: {:regex_match?, [line: 6], ["hello"]}],
            origin_family: :biometric,
            transaction: {:regex_match?, [line: 3], [{:content, [line: 3], nil}, "^Mr.Y|Mr.X{1}$"]}
         },
         constants: %Constants{},
         next_transaction: %Transaction{ data: %TransactionData{}},
         triggers: [
           %Trigger{
             actions: {:__block__, [],
              [
                {:set_type, [line: 9], [{:transfer, [line: 9], nil}]},
                {:add_uco_transfer, [line: 10],
                 [
                   [
                     to: "22368B50D3B2976787CFCC27508A8E8C67483219825F998FC9D6908D54D0FE10",
                     amount: 10.04
                   ]
                 ]}
              ]},
             opts: [at: ~U[2020-10-21 08:56:43Z]],
             type: :datetime
           }
         ]
        }
      }

     Returns an error when there are invalid trigger options

       iex> Interpreter.parse("
       ...>    actions triggered_by: datetime, at: 0000000 do
       ...>    end
       ...> ")
       {:error, "invalid trigger - invalid datetime - arguments at:0 - L1"}

     Returns an error when a invalid term is provided

       iex> Interpreter.parse("
       ...>    actions do
       ...>       System.user_home
       ...>    end
       ...> ")
       {:error, "unexpected token - System - L2:C8"}
  """
  @spec parse(code :: binary()) :: {:ok, Contract.t()} | {:error, reason :: binary()}
  def parse(code) when is_binary(code) do
    with {:ok, ast} <-
           Code.string_to_quoted(String.trim(code), static_atoms_encoder: &atom_encode/2),
         {_, {:ok, %{contract: contract}}} <-
           Macro.traverse(
             ast,
             {:ok, %{scope: :root, contract: %Contract{}}},
             &prewalk/2,
             &postwalk/2
           ) do
      {:ok, contract}
    else
      {:error, reason} ->
        {:error, format_error_reason(reason)}
    end
  catch
    {{:error, reason}, _node} ->
      {:error, format_error_reason(reason)}

    e ->
      e
  end

  defp format_error_reason({metadata, message, cause}) do
    message =
      if message == "unexpected token: " do
        "unexpected token"
      else
        message
      end

    line = Keyword.get(metadata, :line)
    column = Keyword.get(metadata, :column)

    metadata_string = "L#{line}"

    metadata_string =
      if column == nil do
        metadata_string
      else
        metadata_string <> ":C#{column}"
      end

    message =
      if is_atom(message) do
        message |> Atom.to_string() |> String.replace("_", " ")
      else
        message
      end

    "#{message} - #{cause} - #{metadata_string}"
  end

  defp atom_encode(atom, _meta) do
    if atom in Enum.map(@allowed_atoms, &Atom.to_string/1) do
      {:ok, String.to_existing_atom(atom)}
    else
      {:error, "unexpected token"}
    end
  end

  # Whitelist operators
  defp prewalk(node = {:+, _, _}, acc = {:ok, %{scope: {scope, _}}}) when scope != :root,
    do: {node, acc}

  defp prewalk(node = {:-, _, _}, acc = {:ok, %{scope: {scope, _}}}) when scope != :root,
    do: {node, acc}

  defp prewalk(node = {:/, _, _}, acc = {:ok, %{scope: {scope, _}}}) when scope != :root,
    do: {node, acc}

  defp prewalk(node = {:*, _, _}, acc = {:ok, %{scope: {scope, _}}}) when scope != :root,
    do: {node, acc}

  defp prewalk(node = {:>, _, _}, acc = {:ok, %{scope: {scope, _}}}) when scope != :root,
    do: {node, acc}

  defp prewalk(node = {:<, _, _}, acc = {:ok, %{scope: {scope, _}}}) when scope != :root,
    do: {node, acc}

  defp prewalk(node = {:>=, _, _}, acc = {:ok, %{scope: {scope, _}}}) when scope != :root,
    do: {node, acc}

  defp prewalk(node = {:<=, _, _}, acc = {:ok, %{scope: {scope, _}}}) when scope != :root,
    do: {node, acc}

  defp prewalk(node = {:|>, _, _}, acc = {:ok, %{scope: scope}}) when scope != :root,
    do: {node, acc}

  defp prewalk(node = {:==, _, _}, acc = {:ok, %{scope: {scope, _}}}) when scope != :root,
    do: {node, acc}

  # Allow variable assignation inside the actions
  defp prewalk(node = {:=, _, _}, acc = {:ok, %{scope: {:actions, _}}}), do: {node, acc}

  # Whitelist the use of doted statement
  defp prewalk(node = {{:., _, [{_, _, _}, _]}, _, []}, acc) do
    {node, acc}
  end

  # Whitelist the definition of globals in the root
  defp prewalk(node = {:@, _, [{key, _, [val]}]}, acc = {:ok, :root})
       when is_atom(key) and not is_nil(val),
       do: {node, acc}

  # Whitelist the use of globals
  defp prewalk(node = {:@, _, [{key, _, nil}]}, acc = {:ok, _}) when is_atom(key),
    do: {node, acc}

  defp prewalk(node = {:if, _, [_, [do: _]]}, acc = {:ok, %{scope: {:actions, _}}}),
    do: {node, acc}

  defp prewalk(node = {:if, _, [_, [do: _, else: _]]}, acc = {:ok, %{scope: {:actions, _}}}),
    do: {node, acc}

  defp prewalk(node = [do: _, else: _], acc = {:ok, %{scope: {:actions, _}}}), do: {node, acc}

  # Whitelist the used of variables in the actions
  defp prewalk(node = {var, _, nil}, acc = {:ok, %{scope: {:actions, _}}}) when is_atom(var),
    do: {node, acc}

  # Whitelist the in operation
  defp prewalk(node = {:in, _, [_, _]}, acc = {:ok, _}), do: {node, acc}

  # Whitelist maps
  defp prewalk(node = {:%{}, _, fields}, acc = {:ok, _}) when is_list(fields), do: {node, acc}

  # Whitelist the actions section
  defp prewalk(node = {:actions, [line: _], [_, [do: _actions]]}, {:ok, acc = %{scope: :root}}) do
    {node, {:ok, %{acc | scope: :actions}}}
  end

  # Whitelist the triggered_by DSL in the actions
  defp prewalk(
         node = [{:triggered_by, {trigger_type, meta = [line: _], _}} | trigger_opts],
         {:ok, acc = %{scope: :actions}}
       )
       when trigger_type in [:datetime, :interval, :transaction] do
    case valid_trigger_opts(trigger_type, trigger_opts) do
      :ok ->
        {node, {:ok, %{acc | scope: :actions_triggered_by}}}

      {:error, reason} ->
        params = Enum.map(trigger_opts, fn {k, v} -> "#{k}:#{v}" end) |> Enum.join(", ")
        {node, {:error, {meta, "invalid trigger - #{reason}", "arguments #{params}"}}}
    end
  end

  # Define scope of the triggered actions
  defp prewalk(node = {:datetime, [line: _], nil}, {:ok, acc = %{scope: :actions_triggered_by}}) do
    {node, {:ok, %{acc | scope: {:actions, :datetime}}}}
  end

  defp prewalk(node = {:interval, [line: _], nil}, {:ok, acc = %{scope: :actions_triggered_by}}) do
    {node, {:ok, %{acc | scope: {:actions, :interval}}}}
  end

  defp prewalk(
         node = {:transaction, [line: _], nil},
         {:ok, acc = %{scope: :actions_triggered_by}}
       ) do
    {node, {:ok, %{acc | scope: {:actions, :transaction}}}}
  end

  # Whitelist the multiline
  defp prewalk(node = {:__block__, _, _}, acc = {:ok, _}) do
    {node, acc}
  end

  # Whitelist the condition DSL inside transaction trigger
  defp prewalk(
         node = {:condition, [line: _], _},
         {:ok, acc = %{scope: :root}}
       ) do
    {node, {:ok, %{acc | scope: :condition}}}
  end

  # Whitelist the condition 'origin_family'
  defp prewalk(node = [origin_family: {_, [line: _], _}], {:ok, acc = %{scope: :condition}}) do
    {node, {:ok, %{acc | scope: {:condition, :origin_family}}}}
  end

  # Whitelist the condition 'inherit' with brackets
  defp prewalk(node = [inherit: _], {:ok, acc = %{scope: :condition}}) do
    {node, {:ok, %{acc | scope: {:condition, :inherit}}}}
  end

  # Whitelist the condition 'inherit' with comma and without brackets
  defp prewalk(node = {:inherit, _, _}, {:ok, acc = %{scope: :condition}}) do
    {node, {:ok, %{acc | scope: {:condition, :inherit}}}}
  end

  # Whitelist the condition: 'transaction'
  defp prewalk(node = [transaction: _], {:ok, acc = %{scope: :condition}}) do
    {node, {:ok, %{acc | scope: {:condition, :transaction}}}}
  end

  defp prewalk(node = {:transaction, [line: _], _}, {:ok, acc = %{scope: :condition}}) do
    {node, {:ok, %{acc | scope: {:condition, :transaction}}}}
  end

  # Whitelist only the valid origin families
  defp prewalk(node = {family, [line: _], _}, acc = {:ok, %{scope: {:condition, :origin_family}}}) do
    if family in SharedSecrets.list_origin_families() do
      {node, acc}
    else
      {node, {:error, :invalid_origin_family}}
    end
  end

  # Whitelist Access key based with brackets, ie. uco_transfers["Alice"]
  defp prewalk(
         node =
           {{:., _, [Access, :get]}, _, [{{:., [_], [{subject, [_], nil}, field]}, _, []}, key]},
         acc = {:ok, _}
       )
       when subject in [:next_transaction, :contract, :previous_transaction, :transaction] and
              field in @transaction_fields and is_binary(key) do
    case Base.decode16(key, case: :mixed) do
      {:ok, _} ->
        {node, acc}

      _ ->
        {node, {:error, :unexpected_token}}
    end
  end

  # Whitelist access to map field
  defp prewalk(node = {:., _, [Access, :get]}, acc = {:ok, _}), do: {node, acc}

  # Whitelist the use of define set of keyword in the inherit condition
  defp prewalk(node = fields, acc = {:ok, %{scope: {:condition, :inherit}}})
       when is_list(fields) do
    if Enum.all?(fields, fn {field, _} -> field in @inherit_fields end) do
      {node, acc}
    else
      {node, {:error, :unexpected_token}}
    end
  end

  # Whitelist usage of map inside inherit conditions
  defp prewalk(node = {field, {:%{}, _, _}}, acc = {:ok, %{scope: {:condition, :inherit}}})
       when field in @inherit_fields do
    {node, acc}
  end

  defp prewalk(node = {:%{}, _, _}, acc = {:ok, %{scope: {:condition, :inherit}}}) do
    {node, acc}
  end

  # Whitelist usage of functions inside inherit conditions
  defp prewalk(node = {key, _, args}, {:ok, acc = %{scope: scope = {:condition, :inherit}}}) do
    case Enum.find(inherit_conditions_functions(), &(elem(&1, 0) == key)) do
      {_, arity} when length(args) == arity ->
        {node, {:ok, %{acc | scope: {:function, key, scope}}}}

      _ ->
        {node, {:error, :unexpected_token}}
    end
  end

  # Whitelist the use of transaction fields in the transaction condition
  defp prewalk(
         node = {field, [line: _], _},
         acc = {:ok, %{scope: {:condition, :transaction}}}
       )
       when field in @transaction_fields do
    {node, acc}
  end

  # Whitelist the use of transaction and contract fields in the actions
  defp prewalk(
         node = {:., _, [{key, _, _}, field]},
         acc = {:ok, %{scope: {:actions, _}}}
       )
       when key in [:contract, :transaction] and field in @transaction_fields do
    {node, acc}
  end

  defp prewalk(
         node = {field, [line: _], _},
         acc = {:ok, %{scope: {:function, _}}}
       )
       when field in @transaction_fields do
    {node, acc}
  end

  # Whitelist the used of functions in the transaction condition
  defp prewalk(node = {key, _, args}, {:ok, acc = %{scope: scope = {:condition, :transaction}}})
       when is_atom(key) and is_list(args) do
    case Enum.find(transaction_conditions_functions(), &(elem(&1, 0) == key)) do
      {_, arity} when length(args) == arity ->
        {node, {:ok, %{acc | scope: {:function, key, scope}}}}

      _ ->
        {node, {:error, :unexpected_token}}
    end
  end

  defp prewalk(node = {key, _, args}, {:ok, acc = %{scope: scope = {:condition, :transaction}}})
       when is_atom(key) and is_tuple(args) do
    case Enum.find(transaction_conditions_functions(), &(elem(&1, 0) == key)) do
      {_, 1} ->
        {node, {:ok, %{acc | scope: {:function, key, scope}}}}

      _ ->
        {node, {:error, :unexpected_token}}
    end
  end

  # Whitelist the used of functions in the actions
  defp prewalk(node = {key, _, [args]}, {:ok, acc = %{scope: scope = {:actions, _}}})
       when is_atom(key) and is_list(args) do
    case Enum.find(actions_functions(), &(elem(&1, 0) == key)) do
      nil ->
        {node, {:error, :unexpected_token}}

      {_, arity} ->
        if length(args) == arity do
          {node, {:ok, %{acc | scope: {:function, key, scope}}}}
        else
          {node, {:error, :unexpected_token}}
        end
    end
  end

  defp prewalk(node = {key, _, args}, {:ok, acc = %{scope: scope = {:actions, _}}})
       when is_atom(key) and is_list(args) do
    case Enum.find(actions_functions(), &(elem(&1, 0) == key)) do
      nil ->
        {node, {:error, :unexpected_token}}

      {_, arity} ->
        if length(args) == arity do
          {node, {:ok, %{acc | scope: {:function, key, scope}}}}
        else
          {node, {:error, :unexpected_token}}
        end
    end
  end

  defp prewalk(node = {key, _, args}, {:ok, acc = %{scope: scope = {:actions, _}}})
       when is_atom(key) and is_tuple(args) do
    case Enum.find(actions_functions(), &(elem(&1, 0) == key)) do
      {_, 1} ->
        {node, {:ok, %{acc | scope: {:function, key, scope}}}}

      _ ->
        {node, {:error, :unexpected_token}}
    end
  end

  # Whitelist for functions calls for transaction condition
  defp prewalk(node, acc = {:ok, %{scope: {:function, fun, {:condition, :transaction}}}})
       when fun in [:regex_match?, :regex_extract, :json_path_extract, :hash] do
    case node do
      bin when is_binary(bin) ->
        {node, acc}

      {{:., _, [{:contract, _, nil}, field]}, _, _} when field in @transaction_fields ->
        {node, acc}

      {:., _, [{:contract, _, nil}, field]} when field in @transaction_fields ->
        {node, acc}

      {key, _, _} when key in @transaction_fields ->
        {node, acc}

      _ ->
        {node, {:error, :unexpected_token}}
    end
  end

  # Whitelist the parameters of the actions statements
  defp prewalk(
         node = {transaction_type, _, _},
         acc = {:ok, %{scope: {:function, :set_type, {:actions, _}}}}
       )
       when transaction_type in @allowed_transaction_types do
    {node, acc}
  end

  defp prewalk(
         node = [to: address, amount: amount],
         acc = {:ok, %{scope: {:function, :add_uco_transfer, {:actions, _}}}}
       )
       when is_binary(address) and is_float(amount) and amount > 0.0 do
    case Base.decode16(address, case: :mixed) do
      {:ok, _} ->
        {node, acc}

      _ ->
        {node, {:error, :unexpected_token}}
    end
  end

  defp prewalk(
         node = [to: address, amount: amount, nft: nft_address],
         acc = {:ok, %{scope: {:function, :add_nft_transfer, {:actions, _}}}}
       )
       when is_binary(address) and is_float(amount) and is_binary(nft_address) and amount > 0.0 do
    cond do
      match?(:error, Base.decode16(address, case: :mixed)) ->
        {node, {:error, :unexpected_token}}

      match?(:error, Base.decode16(nft_address, case: :mixed)) ->
        {node, {:error, :unexpected_token}}

      true ->
        {node, acc}
    end
  end

  defp prewalk(node, acc = {:ok, %{scope: {:function, :set_content, {:actions, _}}}})
       when is_binary(node) do
    {node, acc}
  end

  defp prewalk(node, {:ok, %{scope: {:function, :set_content, {:actions, _}}}}) do
    {node, {:error, :unexpected_token}}
  end

  defp prewalk(node, acc = {:ok, %{scope: {:function, :set_secret, {:actions, _}}}})
       when is_binary(node) do
    {node, acc}
  end

  defp prewalk(node, {:ok, %{scope: {:function, :set_secret, {:actions, _}}}}) do
    {node, {:error, :unexpected_token}}
  end

  defp prewalk(
         node = [public_key: public_key, encrypted_secret_key: encrypted_secret_key],
         acc = {:ok, %{scope: {:function, :add_authorized_key, {:actions, _}}}}
       )
       when is_binary(public_key) and is_binary(encrypted_secret_key) do
    case Base.decode16(public_key, case: :mixed) do
      {:ok, _} ->
        {node, acc}

      _ ->
        {node, {:error, :unexpected_token}}
    end
  end

  defp prewalk(node, acc = {:ok, %{scope: {:function, :add_recipient, {:actions, _}}}})
       when is_binary(node) do
    case Base.decode16(node, case: :mixed) do
      {:ok, _} ->
        {node, acc}

      _ ->
        {node, {:error, :unexpected_token}}
    end
  end

  defp prewalk(node, {:ok, %{scope: {:function, :add_recipient, {:action, _}}}}) do
    {node, {:error, :unexpected_token}}
  end

  # Whitelist generics
  defp prewalk(true, acc = {:ok, _}), do: {true, acc}
  defp prewalk(false, acc = {:ok, _}), do: {false, acc}
  defp prewalk(number, acc = {:ok, _}) when is_number(number), do: {number, acc}
  defp prewalk(string, acc = {:ok, _}) when is_binary(string), do: {string, acc}
  defp prewalk(atom, acc = {:ok, _}) when is_atom(atom), do: {atom, acc}
  defp prewalk(node = [do: _], acc), do: {node, acc}
  defp prewalk(node = {:do, _}, acc = {:ok, _}), do: {node, acc}

  defp prewalk({key, _} = node, acc = {:ok, _}) when is_atom(key), do: {node, acc}

  # Whitelist keyword list or map key value definition
  defp prewalk(node = {key, _value}, acc = {:ok, _}) when is_atom(key), do: {node, acc}

  # Blacklist anything else
  defp prewalk(node, {:ok, _acc}) do
    {node, {:error, :unexpected_token}}
  end

  defp prewalk(node, e = {:error, _}), do: {node, e}

  # Reset the scope after actions triggered block ending
  defp postwalk(
         node =
           {:actions, [line: _], [[{:triggered_by, {trigger_type, _, _}} | opts], [do: actions]]},
         {:ok, acc}
       ) do
    acc =
      case trigger_type do
        :datetime ->
          datetime =
            opts
            |> Keyword.get(:at)
            |> DateTime.from_unix!()

          Map.update!(
            acc,
            :contract,
            &Contract.add_trigger(&1, :datetime, [at: datetime], actions)
          )

        :interval ->
          interval = Keyword.get(opts, :at)

          Map.update!(
            acc,
            :contract,
            &Contract.add_trigger(&1, :interval, [at: interval], actions)
          )

        :transaction ->
          Map.update!(acc, :contract, &Contract.add_trigger(&1, :transaction, [], actions))
      end

    {node, {:ok, %{acc | scope: :root}}}
  end

  defp postwalk(
         node = {:condition, _, [[origin_family: {family, _, _}]]},
         {:ok, acc}
       ) do
    new_acc =
      acc
      |> Map.update!(:contract, &Contract.add_condition(&1, :origin_family, family))
      |> Map.put(:scope, :root)

    {node, {:ok, new_acc}}
  end

  # Add inherit conditions with brackets
  defp postwalk(
         node = {:condition, _, [[inherit: conditions]]},
         {:ok, acc}
       ) do
    new_acc =
      acc
      |> Map.update!(:contract, &Contract.add_condition(&1, :inherit, conditions))
      |> Map.put(:scope, :root)

    {node, {:ok, new_acc}}
  end

  # Add inherit conditions with comma instead of brackets
  defp postwalk(
         node = {:condition, _, [{:inherit, _, nil}, conditions]},
         {:ok, acc}
       ) do
    new_acc =
      acc
      |> Map.update!(:contract, &Contract.add_condition(&1, :inherit, conditions))
      |> Map.put(:scope, :root)

    {node, {:ok, new_acc}}
  end

  defp postwalk(
         node = {:condition, _, [[transaction: conditions]]},
         {:ok, acc}
       ) do
    new_acc =
      acc
      |> Map.update!(:contract, &Contract.add_condition(&1, :transaction, conditions))
      |> Map.put(:scope, :root)

    {node, {:ok, new_acc}}
  end

  defp postwalk(
         node = {:condition, _, [{:transaction, [line: _], _}, [do: conditions]]},
         {:ok, acc}
       ) do
    new_acc =
      acc
      |> Map.update!(:contract, &Contract.add_condition(&1, :transaction, conditions))
      |> Map.put(:scope, :root)

    {node, {:ok, new_acc}}
  end

  # defp postwalk(node, {:ok, acc = %{scope: {:function, :regex_match?, scope}}})
  #      when is_binary(node) do
  #   {node, {:ok, %{acc | scope: scope}}}
  # end

  # defp postwalk(node, {:ok, acc = %{scope: {:function, :regex_extract, scope}}})
  #      when is_binary(node) do
  #   {node, {:ok, %{acc | scope: scope}}}
  # end

  # defp postwalk(node, {:ok, acc = %{scope: {:function, :json_path_extract, scope}}})
  #      when is_binary(node) do
  #   {node, {:ok, %{acc | scope: scope}}}
  # end

  defp postwalk(node, {:ok, acc = %{scope: {:function, _, scope}}}) do
    {node, {:ok, %{acc | scope: scope}}}
  end

  # Convert Access key string to binary
  defp postwalk(
         {{:., meta1, [Access, :get]}, meta2,
          [{{:., meta3, [{subject, meta4, nil}, field]}, meta5, []}, key]},
         acc
       ) do
    {
      {{:., meta1, [Access, :get]}, meta2,
       [
         {{:., meta3, [{subject, meta4, nil}, field]}, meta5, []},
         Base.decode16!(key, case: :mixed)
       ]},
      acc
    }
  end

  # Convert map key to binary
  defp postwalk({:%{}, meta, params}, acc = {:ok, %{scope: {:condition, :inherit}}}) do
    encoded_params =
      Enum.map(params, fn
        {key, value} when is_atom(key) ->
          case Base.decode16(Atom.to_string(key), case: :mixed) do
            {:ok, bin} ->
              {bin, value}

            :error ->
              {key, value}
          end

        {key, value} ->
          {key, value}
      end)

    {{:%{}, meta, encoded_params}, acc}
  end

  defp postwalk(node, e = {:error, _}), do: throw({e, node})
  defp postwalk(node, acc), do: {node, acc}

  defp valid_trigger_opts(:datetime, at: datetime) do
    if length(Integer.digits(datetime)) != 10 do
      {:error, "invalid datetime"}
    else
      case DateTime.from_unix(datetime) do
        {:ok, _} ->
          :ok

        _ ->
          {:error, "invalid datetime"}
      end
    end
  end

  defp valid_trigger_opts(:interval, at: interval) do
    case CronParser.parse(interval) do
      {:ok, _} ->
        :ok

      {:error, _} ->
        {:error, "invalid interval"}
    end
  end

  defp valid_trigger_opts(:transaction, []), do: :ok
  defp valid_trigger_opts(_, _), do: {:error, "unexpected token"}

  @doc """

  ## Examples

      iex> Interpreter.execute_actions(%Contract{ triggers: [ %Contract.Trigger{type: :transaction, actions: {:set_type, [line: 4], [{:transfer, [line: 4], nil}]}}]}, :transaction)
      %Contract{
        triggers: [
         %Trigger{actions: {:set_type, [line: 4], [{:transfer, [line: 4], nil}]}, opts: [], type: :transaction}
        ],
        next_transaction: %Transaction{type: :transfer, data: %TransactionData{}}
      }

      iex> Interpreter.execute_actions(%Contract{ triggers: [ %Contract.Trigger{type: :transaction, actions: {:__block__, [],
      ...>  [
      ...>    {:set_type, [], [{:transfer, [], nil}]},
      ...>    {:add_uco_transfer, [], [[to: {:hash, [], ["@Alice2"]}, amount: 10.04]]}
      ...>  ]}}] }, :transaction)
      %Contract{
         triggers: [
           %Trigger{
             actions: {:__block__, [], [
               {:set_type, [], [{:transfer, [], nil}]},
               {:add_uco_transfer, [], [[to: {:hash, [], ["@Alice2"]}, amount: 10.04]]}
             ]},
             opts: [],
             type: :transaction
           }
         ],
         next_transaction: %Transaction{
           type: :transfer,
           data: %TransactionData{
              ledger: %Ledger{
                uco: %UCOLedger{
                  transfers: [
                    %UCOLedger.Transfer{ to: <<0, 252, 103, 8, 52, 151, 127, 195, 65, 104, 171, 247, 238, 227, 111, 140, 89,
                      49, 204, 58, 141, 215, 66, 253, 40, 183, 165, 117, 120, 80, 100, 232, 95>>, amount: 10.04}
                  ]
                }
              }
           }
         }
      }
  """
  def execute_actions(contract = %Contract{triggers: triggers}, trigger_type, constants \\ []) do
    %Contract.Trigger{actions: actions} = Enum.find(triggers, &(&1.type == trigger_type))

    case actions do
      {:__block__, _, actions} ->
        Enum.reduce(actions, contract, fn {function, _, args}, acc ->
          arguments = Enum.map(args, &eval_argument(&1, constants))
          apply(ActionStatements, function, [acc | arguments])
        end)

      {:if, _, [condition, clauses]} ->
        evaluate_if_statement(condition, clauses, contract, constants)

      {function, _, args} ->
        evaluate_function(function, args, contract, constants)
    end
  end

  defp evaluate_if_statement(condition, clauses, contract, constants) do
    do_operations = Keyword.get(clauses, :do)
    else_operations = Keyword.get(clauses, :else, [])

    if execute(condition, constants) do
      case do_operations do
        {:block, _, actions} ->
          Enum.reduce(actions, contract, fn {function, _, args}, acc ->
            evaluate_function(function, args, acc, constants)
          end)

        {function, _, args} ->
          evaluate_function(function, args, contract, constants)
      end
    else
      case else_operations do
        {:block, _, actions} ->
          Enum.reduce(actions, contract, fn {function, _, args}, acc ->
            evaluate_function(function, args, acc, constants)
          end)

        {function, _, args} ->
          evaluate_function(function, args, contract, constants)

        [] ->
          nil
      end
    end
  end

  defp evaluate_function(function, args, contract, constants) do
    arguments = Enum.map(args, &eval_argument(&1, constants))
    apply(ActionStatements, function, [contract | arguments])
  end

  defp eval_argument({arg, _, _}, constants), do: execute(Macro.to_string(arg), constants)

  defp eval_argument(args, constants) when is_list(args) do
    Enum.map(args, fn
      {k, v} ->
        output = execute(Macro.to_string(v), constants)
        {k, output}

      arg ->
        execute(Macro.to_string(arg), constants)
    end)
  end

  defp eval_argument(arg, constants), do: execute(Macro.to_string(arg), constants)

  @doc ~S"""
  Interpret some quoted code with constants as bindings and loading the STD functions into the context of execution

   ## Examples

     Return function call from the standard library

       iex> Interpreter.execute("regex_match?(content, \"^Mr.Y|Mr.X{1}$\")", content: "Mr.Y")
       true
  """
  @spec execute(binary(), Keyword.t()) :: any()
  def execute(code, constants \\ [])

  def execute(code, constants) when is_binary(code),
    do: do_execute(Code.string_to_quoted!(code), constants)

  def execute(code, constants), do: do_execute(code, constants)

  defp do_execute(code, constants) do
    library_function_names =
      Enum.reject(Library.__info__(:functions), fn {fun, _} -> fun == :allowed_atoms end)

    library_bindings =
      Enum.map(library_function_names, fn {fun, _} ->
        {fun, fn params -> apply(Library, fun, params) end}
      end)

    bindings = library_bindings ++ constants ++ Enum.map(@allowed_transaction_types, &{&1, &1})
    execute_with_custom_function_bindings(code, bindings, library_function_names)
  end

  @doc ~S"""
  Execute the inherit condition on the given subset

  ## Examples

      iex> Interpreter.execute_inherit_condition("regex_match?(\"hello\")", "hello")
      true

      iex> Interpreter.execute_inherit_condition("hash()", "hello")
      <<0, 44, 242, 77, 186, 95, 176, 163, 14, 38, 232, 59, 42, 197, 185, 226, 158, 27,
      22, 30, 92, 31, 167, 66, 94, 115, 4, 51, 98, 147, 139, 152, 36>>
  """
  @spec execute_inherit_condition(binary(), term()) :: term()
  def execute_inherit_condition(code, subject) when is_binary(code) do
    bindings =
      Enum.map(inherit_conditions_functions(), fn {fun, _arity} ->
        {fun, fn params -> apply(Library, fun, [subject | params]) end}
      end)

    execute_with_custom_function_bindings(
      Code.string_to_quoted!(code),
      bindings,
      inherit_conditions_functions()
    )
  end

  defp execute_with_custom_function_bindings(code, bindings, function_list) do
    new_ast = Macro.postwalk(code, &append_dot(&1, function_list))
    {result, _} = Code.eval_quoted(new_ast, bindings)
    result
  end

  defp append_dot(ast = {key, meta, params}, function_list) do
    case Enum.find(function_list, &(elem(&1, 0) == key)) do
      {_, _arity} ->
        {{:., meta, [{key, meta, nil}]}, meta, [params]}

      nil ->
        ast
    end
  end

  defp append_dot(ast, _), do: ast

  @doc """
  Determine if the contract can be executed based on some condition to assert.

  A boolean must return from the condition code to ensure the actions can be executed

  ## Examples

        iex> Interpreter.can_execute?("next_transaction.code == previous_transaction.code", previous_transaction: %{code: "abc"}, next_transaction: %{code: "bcd"})
        false

     Return the when not condition are provided, so the actions can be executed

        iex> Interpreter.can_execute?(nil, content: "Mr.Y")
        true
  """
  @spec can_execute?(nil | binary(), Keyword.t()) :: boolean()
  def can_execute?(nil, _), do: true
  def can_execute?("", _), do: true

  def can_execute?(condition, constants) when is_binary(condition) and is_list(constants) do
    execute(condition, constants) == true
  end

  defp transaction_conditions_functions do
    [
      {:hash, 1},
      {:regex_match?, 2},
      {:regex_extract, 2},
      {:json_path_extract, 2}
    ]
  end

  defp inherit_conditions_functions do
    [
      {:hash, 1},
      {:regex_match?, 1},
      {:regex_extract, 1},
      {:json_path_extract, 1}
    ]
  end

  defp actions_functions do
    [
      {:set_type, 1},
      {:add_uco_transfer, 2},
      {:add_nft_transfer, 3},
      {:set_content, 1},
      {:set_code, 1},
      {:add_authorized_key, 2},
      {:set_secret, 1},
      {:add_recipient, 1}
    ]
  end
end
