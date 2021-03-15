defmodule Uniris.Contracts.Interpreter do
  @moduledoc false

  alias Crontab.CronExpression.Parser, as: CronParser

  alias __MODULE__.Library
  alias __MODULE__.TransactionStatements

  alias Uniris.Contracts.Contract

  alias Uniris.SharedSecrets

  @library_functions_names Library.__info__(:functions) |> Enum.map(&Atom.to_string(elem(&1, 0)))
  @transaction_statements_functions_names TransactionStatements.__info__(:functions)
                                          |> Enum.map(&Atom.to_string(elem(&1, 0)))

  @transaction_fields [
    "address",
    "type",
    "timestamp",
    "previous_signature",
    "previous_public_key",
    "origin_signature",
    "content",
    "keys",
    "code",
    "uco_ledger",
    "nft_ledger",
    "uco_transfers",
    "nft_transfers",
    "authorized_keys",
    "secret",
    "recipients"
  ]

  @inherit_fields [
    "code",
    "secret",
    "content",
    "uco_transfers",
    "nft_transfers",
    "type"
  ]

  @allowed_transaction_types ["transfer", "nft", "hosting"]

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
      ...>   condition oracle: json_path_extract(content, \"$.uco.eur\") > 1
      ...>
      ...>    actions triggered_by: datetime, at: 1603270603 do
      ...>      new_content = \"Sent #{10.04}\"
      ...>      set_type transfer
      ...>      set_content new_content
      ...>      add_uco_transfer to: \"22368B50D3B2976787CFCC27508A8E8C67483219825F998FC9D6908D54D0FE10\", amount: 10.04
      ...>    end
      ...>
      ...>    actions triggered_by: oracle do
      ...>      set_content \"uco price changed\"
      ...>    end
      ...> ")
      {:ok,
        %Contract{
         conditions: %Conditions{
            inherit: {
                    :and,
                    [line: 0],
                    [
                      {
                        :and,
                        [line: 0],
                        [
                          {
                            :and,
                            [line: 0],
                            [
                              {
                                :and,
                                [line: 0],
                                [
                                  {
                                    :and,
                                    [line: 0],
                                    [
                                      {:==, [line: 0], [{:get_in, [line: 0], [{:scope, [line: 0], nil}, ["next", "code"]]}, {:get_in, [line: 0], [{:scope, [line: 0], nil}, ["prev", "code"]]}]},
                                      {
                                        :==,
                                        [line: 6],
                                        [
                                          {
                                            {:., [line: 6], [{:__aliases__, [alias: Uniris.Contracts.Interpreter.Library], [:Library]}, :regex_match?]},
                                            [line: 6],
                                            [{:get_in, [line: 6], [{:scope, [line: 6], nil}, ["next", "content"]]}, "hello"]
                                          },
                                          {:get_in, [line: 6], [{:scope, [line: 6], nil}, ["next", "content"]]}
                                        ]
                                      }
                                    ]
                                  },
                                  {:==, [line: 0], [{:get_in, [line: 0], [{:scope, [line: 0], nil}, ["next", "nft_transfers"]]}, {:get_in, [line: 0], [{:scope, [line: 0], nil}, ["prev", "nft_transfers"]]}]}
                                ]
                              },
                              {:==, [line: 0], [{:get_in, [line: 0], [{:scope, [line: 0], nil}, ["next", "secret"]]}, {:get_in, [line: 0], [{:scope, [line: 0], nil}, ["prev", "secret"]]}]}
                            ]
                          },
                          {:==, [line: 0], [{:get_in, [line: 0], [{:scope, [line: 0], nil}, ["next", "type"]]}, {:get_in, [line: 0], [{:scope, [line: 0], nil}, ["prev", "type"]]}]}
                        ]
                      },
                      {:==, [line: 0], [{:get_in, [line: 0], [{:scope, [line: 0], nil}, ["next", "uco_transfers"]]}, {:get_in, [line: 0], [{:scope, [line: 0], nil}, ["prev", "uco_transfers"]]}]}
                    ]
                  },
            oracle: {
                    :>,
                    [line: 8],
                    [
                      {
                        {:., [line: 8], [{:__aliases__, [alias: Uniris.Contracts.Interpreter.Library], [:Library]}, :json_path_extract]},
                        [line: 8],
                        [{:get_in, [line: 8], [{:scope, [line: 8], nil}, ["data"]]}, "content", "$.uco.eur"]
                      },
                      1
                    ]
                  },
            origin_family: :biometric,
            transaction: {{:., [line: 3], [{:__aliases__, [alias: Uniris.Contracts.Interpreter.Library], [:Library]}, :regex_match?]}, [line: 3], [{:get_in, [line: 3], [{:scope, [line: 3], nil}, ["content"]]}, "^Mr.Y|Mr.X{1}$"]}
         },
         constants: %Constants{},
         next_transaction: %Transaction{ data: %TransactionData{}},
         triggers: [
           %Trigger{
             actions: {:__block__, [],
              [
                {:=, [line: 11], [{:scope, [line: 11], nil}, {{:., [line: 11], [{:__aliases__, [line: 11], [:Map]}, :put]}, [line: 11], [{:scope, [line: 11], nil}, "new_content", "Sent 10.04"]}]},
                {
                  :=,
                  [line: 12],
                  [
                    {:scope, [line: 12], nil},
                    {:update_in, [line: 12], [{:scope, [line: 12], nil}, ["contract"], {:&, [line: 12], [{{:., [line: 12], [{:__aliases__, [alias: Uniris.Contracts.Interpreter.TransactionStatements], [:TransactionStatements]}, :set_type]}, [line: 12], [{:&, [line: 12], [1]}, "transfer"]}]}]}
                  ]
                },
                {
                  :=,
                  [line: 13],
                  [
                    {:scope, [line: 13], nil},
                    {:update_in, [line: 13], [{:scope, [line: 13], nil}, ["contract"], {:&, [line: 13], [{{:., [line: 13], [{:__aliases__, [alias: Uniris.Contracts.Interpreter.TransactionStatements], [:TransactionStatements]}, :set_content]}, [line: 13], [{:&, [line: 13], [1]}, {:get_in, [line: 13], [{:scope, [line: 13], nil}, ["new_content"]]}]}]}]}
                  ]
                },
                {
                  :=,
                  [line: 14],
                  [
                    {:scope, [line: 14], nil},
                    {:update_in, [line: 14], [{:scope, [line: 14], nil}, ["contract"], {:&, [line: 14], [{{:., [line: 14], [{:__aliases__, [alias: Uniris.Contracts.Interpreter.TransactionStatements], [:TransactionStatements]}, :add_uco_transfer]}, [line: 14], [{:&, [line: 14], [1]}, [{"to", <<34, 54, 139, 80, 211, 178, 151, 103, 135, 207, 204, 39, 80, 138, 142, 140, 103, 72, 50, 25, 130, 95, 153, 143, 201, 214, 144, 141, 84, 208, 254, 16>>}, {"amount", 10.04}]]}]}]}
                  ]
                }
              ]},
             opts: [at: ~U[2020-10-21 08:56:43Z]],
             type: :datetime
           },
           %Trigger{actions: {
              :=,
              [line: 18],
              [
                {:scope, [line: 18], nil},
                {:update_in, [line: 18], [{:scope, [line: 18], nil}, ["contract"], {:&, [line: 18], [{{:., [line: 18], [{:__aliases__, [alias: Uniris.Contracts.Interpreter.TransactionStatements], [:TransactionStatements]}, :set_content]}, [line: 18], [{:&, [line: 18], [1]}, "uco price changed"]}]}]}
              ]
           }, opts: [], type: :oracle}
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
       {:error, "unexpected token - System - L2"}
  """
  @spec parse(code :: binary()) :: {:ok, Contract.t()} | {:error, reason :: binary()}
  def parse(code) when is_binary(code) do
    with {:ok, ast} <-
           Code.string_to_quoted(String.trim(code),
             static_atoms_encoder: &atom_encoder/2
           ),
         {_, {:ok, %{contract: contract}}} <-
           Macro.traverse(
             ast,
             {:ok, %{scope: :root, contract: %Contract{}}},
             &prewalk/2,
             &postwalk/2
           ) do
      {:ok, contract}
    else
      {_node, {:error, reason}} ->
        {:error, format_error_reason(reason)}

      {:error, reason} ->
        {:error, format_error_reason(reason)}
    end
  catch
    {{:error, reason}, {:., metadata, [{:__aliases__, _, atom: cause}, _]}} ->
      {:error, format_error_reason({metadata, reason, cause})}

    {{:error, :unexpected_token}, {:atom, key}} ->
      {:error, format_error_reason({[], "unexpected_token", key})}

    {:error, reason = {_metadata, _message, _cause}} ->
      {:error, format_error_reason(reason)}
  end

  defp atom_encoder(atom, _) do
    if atom in ["if"] do
      {:ok, String.to_atom(atom)}
    else
      {:ok, {:atom, atom}}
    end
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

  # # Whitelist the definition of globals in the root
  # defp prewalk(node = {:@, _, [{key, _, [val]}]}, acc = {:ok, :root})
  #      when is_atom(key) and not is_nil(val),
  #      do: {node, acc}

  # # Whitelist the use of globals
  # defp prewalk(node = {:@, _, [{key, _, nil}]}, acc = {:ok, _}) when is_atom(key),
  #   do: {node, acc}

  # Whitelist conditional oeprators
  defp prewalk(node = {:if, _, [_, [do: _]]}, acc = {:ok, %{scope: {:actions, _}}}),
    do: {node, acc}

  defp prewalk(node = {:if, _, [_, [do: _, else: _]]}, acc = {:ok, %{scope: {:actions, _}}}),
    do: {node, acc}

  defp prewalk(node = {:else, _}, acc = {:ok, %{scope: {:actions, _}}}),
    do: {node, acc}

  defp prewalk(node = [do: _, else: _], acc = {:ok, %{scope: {:actions, _}}}), do: {node, acc}
  defp prewalk(node = :else, acc = {:ok, %{scope: {:actions, _}}}), do: {node, acc}

  defp prewalk(node = {:and, _, _}, acc = {:ok, _}), do: {node, acc}
  defp prewalk(node = {:or, _, _}, acc = {:ok, _}), do: {node, acc}

  # Whitelist the in operation
  defp prewalk(node = {:in, _, [_, _]}, acc = {:ok, _}), do: {node, acc}

  # Whitelist maps
  defp prewalk(node = {:%{}, _, fields}, acc = {:ok, _}) when is_list(fields), do: {node, acc}

  defp prewalk(node = {key, _val}, acc) when is_binary(key) do
    {node, acc}
  end

  # Whitelist custom atom
  defp prewalk(node = :atom, acc), do: {node, acc}

  defp prewalk(node = {{:atom, "actions"}, _, _}, {:ok, acc = %{scope: :root}}) do
    {node, {:ok, %{acc | scope: :actions}}}
  end

  # Whitelist the triggered_by DSL in the actions
  defp prewalk(
         node = [
           {{:atom, "triggered_by"}, {{:atom, trigger_type}, meta = [line: _], _}} | trigger_opts
         ],
         {:ok, acc = %{scope: :actions}}
       )
       when trigger_type in ["datetime", "interval", "transaction", "oracle"] do
    case valid_trigger_opts(trigger_type, trigger_opts) do
      :ok ->
        {node, {:ok, %{acc | scope: :actions_triggered_by}}}

      {:error, reason} ->
        params = Enum.map(trigger_opts, fn {{:atom, k}, v} -> "#{k}:#{v}" end) |> Enum.join(", ")
        throw({:error, {meta, "invalid trigger - #{reason}", "arguments #{params}"}})
    end
  end

  # Define scope of the triggered actions
  defp prewalk(
         node = {{:atom, "datetime"}, [line: _], nil},
         {:ok, acc = %{scope: :actions_triggered_by}}
       ) do
    {node, {:ok, %{acc | scope: {:actions, :datetime}}}}
  end

  defp prewalk(
         node = {{:atom, "interval"}, [line: _], nil},
         {:ok, acc = %{scope: :actions_triggered_by}}
       ) do
    {node, {:ok, %{acc | scope: {:actions, :interval}}}}
  end

  defp prewalk(
         node = {{:atom, "oracle"}, [line: _], nil},
         {:ok, acc = %{scope: :actions_triggered_by}}
       ) do
    {node, {:ok, %{acc | scope: {:actions, :oracle}}}}
  end

  defp prewalk(
         node = {{:atom, "transaction"}, [line: _], nil},
         {:ok, acc = %{scope: :actions_triggered_by}}
       ) do
    {node, {:ok, %{acc | scope: {:actions, :transaction}}}}
  end

  # Whitelist the multiline
  defp prewalk(node = {{:__block__, _, _}}, acc = {:ok, _}) do
    {node, acc}
  end

  defp prewalk(node = {:__block__, _, _}, acc = {:ok, _}) do
    {node, acc}
  end

  # Whitelist the condition DSL inside transaction trigger
  defp prewalk(
         node = {{:atom, "condition"}, [line: _], _},
         {:ok, acc = %{scope: :root}}
       ) do
    {node, {:ok, %{acc | scope: :condition}}}
  end

  # Whitelist the condition 'origin_family'
  defp prewalk(
         node = [{{:atom, "origin_family"}, {_, [line: _], _}}],
         {:ok, acc = %{scope: :condition}}
       ) do
    {node, {:ok, %{acc | scope: {:condition, :origin_family}}}}
  end

  # Whitelist the condition 'inherit' with brackets
  defp prewalk(node = [{{:atom, "inherit"}, _}], {:ok, acc = %{scope: :condition}}) do
    {node, {:ok, %{acc | scope: {:condition, :inherit}}}}
  end

  # Whitelist the condition 'inherit' with comma and without brackets
  defp prewalk(node = {{:atom, "inherit"}, _, _}, {:ok, acc = %{scope: :condition}}) do
    {node, {:ok, %{acc | scope: {:condition, :inherit}}}}
  end

  # Whitelist the condition: 'transaction'
  defp prewalk(node = [{{:atom, "transaction"}, _}], {:ok, acc = %{scope: :condition}}) do
    {node, {:ok, %{acc | scope: {:condition, :transaction}}}}
  end

  defp prewalk(node = {{:atom, "transaction"}, [line: _], _}, {:ok, acc = %{scope: :condition}}) do
    {node, {:ok, %{acc | scope: {:condition, :transaction}}}}
  end

  defp prewalk(node = {:atom, "transaction"}, {:ok, acc = %{scope: {:condition, :transaction}}}) do
    {node, {:ok, %{acc | scope: {:condition, :transaction}}}}
  end

  # Whitelist the condition: 'oracle'
  defp prewalk(node = [{{:atom, "oracle"}, _}], {:ok, acc = %{scope: :condition}}) do
    {node, {:ok, %{acc | scope: {:condition, :oracle}}}}
  end

  # Whitelist only the valid origin families
  defp prewalk(
         node = {{:atom, family}, [line: _], _},
         acc = {:ok, %{scope: {:condition, :origin_family}}}
       ) do
    authorized_families = SharedSecrets.list_origin_families() |> Enum.map(&Atom.to_string/1)

    if family in authorized_families do
      {node, acc}
    else
      {node, {:error, :invalid_origin_family}}
    end
  end

  # Whitelist Access key based with brackets, ie. uco_transfers["Alice"]
  defp prewalk(
         node =
           {{:., metadata, [Access, :get]}, _,
            [{{:., [_], [{{:atom, subject}, [_], nil}, {:atom, field}]}, _, []}, key]},
         acc = {:ok, _}
       )
       when subject in [:next_transaction, :contract, :previous_transaction, :transaction] and
              field in @transaction_fields and is_binary(key) do
    case Base.decode16(key, case: :mixed) do
      {:ok, _} ->
        {node, acc}

      _ ->
        {node, {:error, {metadata, "unexpected token", ""}}}
    end
  end

  # Whitelist access to map field
  defp prewalk(node = {:., _, [Access, :get]}, acc = {:ok, _}), do: {node, acc}

  # Whitelist usage of map inside inherit conditions
  defp prewalk(
         node = {{:atom, field}, {:%{}, _, _}},
         acc = {:ok, %{scope: {:condition, :inherit}}}
       )
       when field in @inherit_fields do
    {node, acc}
  end

  defp prewalk(node = {:%{}, _, _}, acc = {:ok, %{scope: {:condition, :inherit}}}) do
    {node, acc}
  end

  defp prewalk(node = [{{:atom, _}, _} | _], acc = {:ok, %{scope: {:condition, :inherit}}}) do
    {node, acc}
  end

  # Whitelist the use of transaction fields in the transaction condition
  defp prewalk(
         node = {{:atom, field}, [line: _], _},
         acc = {:ok, %{scope: {:condition, :transaction}}}
       )
       when field in @transaction_fields do
    {node, acc}
  end

  # Whitelist the use of transaction fields in the transaction condition
  defp prewalk(
         node = {{:atom, field}, [line: _], _},
         acc = {:ok, %{scope: {:condition, :oracle}}}
       )
       when field in @transaction_fields do
    {node, acc}
  end

  # Whitelist the use of transaction and contract fields in the actions
  defp prewalk(
         node = {:., _, [{{:atom, key}, _, _}, {:atom, field}]},
         acc = {:ok, %{scope: {:actions, _}}}
       )
       when key in ["contract", "transaction"] and field in @transaction_fields do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, field}, [line: _], _},
         acc = {:ok, %{scope: {:function, _}}}
       )
       when field in @transaction_fields do
    {node, acc}
  end

  # Whitelist the used of functions in the condition
  defp prewalk(
         node = {{:atom, "regex_match?"}, _, [input, search]},
         acc = {:ok, %{scope: {:condition, condition}}}
       )
       when condition in [:transaction, :oracle] and is_binary(input) and is_binary(search) do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "regex_match?"}, _, [{{:atom, key}, _, _}, search]},
         acc = {:ok, %{scope: {:condition, condition}}}
       )
       when condition in [:transaction, :oracle] and key in @transaction_fields and
              is_binary(search) do
    {node, acc}
  end

  defp prewalk(
         node =
           {{:atom, "regex_match?"}, _,
            [{{:., _, [{{:atom, "contract"}, _, nil}, field]}, _, _}, search]},
         acc = {:ok, %{scope: {:condition, condition}}}
       )
       when condition in [:transaction, :oracle] and field in @transaction_fields and
              is_binary(search) do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "json_path_extract"}, _, [input, search]},
         acc = {:ok, %{scope: {:condition, condition}}}
       )
       when condition in [:transaction, :oracle] and is_binary(input) and is_binary(search) do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "json_path_extract"}, _, [{{:atom, key}, _, _}, search]},
         acc = {:ok, %{scope: {:condition, condition}}}
       )
       when condition in [:transaction, :oracle] and key in @transaction_fields and
              is_binary(search) do
    {node, acc}
  end

  defp prewalk(
         node =
           {{:atom, "json_path_extract"}, _,
            [{{:., _, [{{:atom, "contract"}, _, nil}, field]}, _, _}, search]},
         acc = {:ok, %{scope: {:condition, condition}}}
       )
       when condition in [:transaction, :oracle] and field in @transaction_fields and
              is_binary(search) do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "hash"}, _, [data]},
         acc = {:ok, %{scope: {:condition, condition}}}
       )
       when condition in [:transaction, :oracle] and is_binary(data) do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "hash"}, _, [{{:atom, key}, _, _}]},
         acc = {:ok, %{scope: {:condition, condition}}}
       )
       when condition in [:transaction, :oracle] and key in @transaction_fields do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "hash"}, _, [{{:., _, [{{:atom, "contract"}, _, nil}, field]}, _, _}]},
         acc = {:ok, %{scope: {:condition, condition}}}
       )
       when condition in [:transaction, :oracle] and field in @transaction_fields do
    {node, acc}
  end

  defp prewalk(node = [{{:atom, field}, _}], acc = {:ok, %{scope: {:condition, :inherit}}})
       when field in @transaction_fields do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "regex_match?"}, _, [search]},
         acc = {:ok, %{scope: {:condition, :inherit}}}
       )
       when is_binary(search) do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "json_path_extract"}, _, [search]},
         acc = {:ok, %{scope: {:condition, :inherit}}}
       )
       when is_binary(search) do
    {node, acc}
  end

  defp prewalk(node = {{:atom, "hash"}, _, [data]}, acc = {:ok, %{scope: {:condition, :inherit}}})
       when is_binary(data) do
    {node, acc}
  end

  # Whitelist the used of functions in the actions
  defp prewalk(
         node = {{:atom, "set_type"}, _metadata, [_]},
         {:ok, acc = %{scope: scope = {:actions, _}}}
       ) do
    {node, {:ok, %{acc | scope: {:function, "set_type", scope}}}}
  end

  defp prewalk(
         node = {{:atom, transaction_type}, _, _},
         acc = {:ok, %{scope: {:function, "set_type", {:actions, _}}}}
       )
       when transaction_type in @allowed_transaction_types do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, _}, _, nil},
         acc = {:ok, %{scope: {:function, "set_type", {:actions, _}}}}
       ) do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "set_content"}, _metadata, [_content]},
         {:ok, acc = %{scope: scope = {:actions, _}}}
       ) do
    {node, {:ok, %{acc | scope: {:function, "set_content", scope}}}}
  end

  defp prewalk(
         node = [{{:atom, _}, _, nil}],
         acc = {:ok, %{scope: {:function, "set_content", {:actions, _}}}}
       ) do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "add_uco_transfer"}, _metadata, [_]},
         {:ok, acc = %{scope: scope = {:actions, _}}}
       ) do
    {node, {:ok, %{acc | scope: {:function, "add_uco_transfer", scope}}}}
  end

  defp prewalk(
         node = [{{:atom, "to"}, _to}, {{:atom, "amount"}, _amount}],
         acc = {:ok, %{scope: {:function, "add_uco_transfer", {:actions, _}}}}
       ) do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "add_nft_transfer"}, _metadata, [_]},
         {:ok, acc = %{scope: scope = {:actions, _}}}
       ) do
    {node, {:ok, %{acc | scope: {:function, "add_nft_transfer", scope}}}}
  end

  defp prewalk(
         node = [
           {{:atom, "to"}, _to},
           {{:atom, "amount"}, _amount},
           {{:atom, "nft"}, _nft}
         ],
         acc = {:ok, %{scope: {:function, "add_nft_transfer", {:actions, _}}}}
       ) do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "set_secret"}, _metadata, [_]},
         acc = {:ok, _acc = %{scope: _scope = {:actions, _}}}
       ) do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "add_authorized_key"}, _metadata, [_secret]},
         {:ok, acc = %{scope: scope = {:actions, _}}}
       ) do
    {node, {:ok, %{acc | scope: {:function, "add_authorized_key", scope}}}}
  end

  defp prewalk(
         node = [
           {{:atom, "public_key"}, _public_key},
           {{:atom, "encrypted_secret_key"}, _encrypted_secret_key}
         ],
         acc = {:ok, %{scope: {:function, "add_authorized_key", {:actions, _}}}}
       ) do
    {node, acc}
  end

  defp prewalk(
         node = {{:atom, "add_recipient"}, _metadata, [_recipient]},
         acc = {:ok, _acc = %{scope: _scope = {:actions, _}}}
       ) do
    {node, acc}
  end

  # Whitelist generics
  defp prewalk(true, acc = {:ok, _}), do: {true, acc}
  defp prewalk(false, acc = {:ok, _}), do: {false, acc}
  defp prewalk(number, acc = {:ok, _}) when is_number(number), do: {number, acc}
  defp prewalk(string, acc = {:ok, _}) when is_binary(string), do: {string, acc}
  defp prewalk(node = [do: _], acc = {:ok, _}), do: {node, acc}
  defp prewalk(node = {:do, _}, acc = {:ok, _}), do: {node, acc}
  defp prewalk(node = :do, acc = {:ok, _}), do: {node, acc}
  defp prewalk(node = {{:atom, key}, _}, acc = {:ok, _}) when is_binary(key), do: {node, acc}
  defp prewalk(node = {{:atom, key}, _, _}, acc = {:ok, _}) when is_binary(key), do: {node, acc}
  defp prewalk(node = {:atom, key}, acc) when is_binary(key), do: {node, acc}

  # Whitelist interpolation of strings
  defp prewalk(
         node =
           {:<<>>, _,
            [{:"::", _, [{{:., [line: 1], [Kernel, :to_string]}, _, _}, {:binary, _, nil}]}]},
         acc
       ) do
    {node, acc}
  end

  defp prewalk(
         node =
           {:<<>>, _,
            [
              _,
              {:"::", _, [{{:., _, [Kernel, :to_string]}, _, _}, {:binary, _, nil}]}
            ]},
         acc
       ) do
    {node, acc}
  end

  defp prewalk(node = {:"::", _, [{{:., _, [Kernel, :to_string]}, _, _}, {:binary, _, nil}]}, acc) do
    {node, acc}
  end

  defp prewalk(node = {{:., _, [Kernel, :to_string]}, _, _}, acc) do
    {node, acc}
  end

  defp prewalk(node = {:., _, [Kernel, :to_string]}, acc) do
    {node, acc}
  end

  defp prewalk(node = Kernel, acc), do: {node, acc}
  defp prewalk(node = :to_string, acc), do: {node, acc}
  defp prewalk(node = {:binary, _, nil}, acc), do: {node, acc}

  # Blacklist anything else
  defp prewalk(node, {:ok, _acc}) do
    throw({{:error, :unexpected_token}, node})
  end

  defp prewalk(node, e = {:error, _}), do: {node, e}

  # Reset the scope after actions triggered block ending
  defp postwalk(
         node =
           {{:atom, "actions"}, [line: _],
            [[{{:atom, "triggered_by"}, {{:atom, trigger_type}, _, _}} | opts], [do: actions]]},
         {:ok, acc}
       ) do
    actions =
      inject_bindings_and_functions(actions,
        bindings: %{
          "contract" => Enum.map(@transaction_fields, &{&1, ""}) |> Enum.into(%{}),
          "transaction" => Enum.map(@transaction_fields, &{&1, ""}) |> Enum.into(%{}),
          "data" => ""
        }
      )

    acc =
      case trigger_type do
        "datetime" ->
          [{{:atom, "at"}, timestamp}] = opts
          datetime = DateTime.from_unix!(timestamp)

          Map.update!(
            acc,
            :contract,
            &Contract.add_trigger(&1, :datetime, [at: datetime], actions)
          )

        "interval" ->
          [{{:atom, "at"}, interval}] = opts

          Map.update!(
            acc,
            :contract,
            &Contract.add_trigger(&1, :interval, [at: interval], actions)
          )

        "transaction" ->
          Map.update!(acc, :contract, &Contract.add_trigger(&1, :transaction, [], actions))

        "oracle" ->
          Map.update!(acc, :contract, &Contract.add_trigger(&1, :oracle, [], actions))
      end

    {node, {:ok, %{acc | scope: :root}}}
  end

  defp postwalk(
         node =
           {{:atom, "condition"}, _, [[{{:atom, "origin_family"}, {{:atom, family}, _, _}}]]},
         {:ok, acc}
       ) do
    new_acc =
      acc
      |> Map.update!(
        :contract,
        &Contract.add_condition(&1, :origin_family, String.to_existing_atom(family))
      )
      |> Map.put(:scope, :root)

    {node, {:ok, new_acc}}
  end

  # Add inherit conditions with brackets
  defp postwalk(
         node = {{:atom, "condition"}, _, [[{{:atom, "inherit"}, conditions}]]},
         {:ok, acc}
       ) do
    new_acc =
      acc
      |> Map.update!(
        :contract,
        &Contract.add_condition(&1, :inherit, aggregate_inherit_conditions(conditions))
      )
      |> Map.put(:scope, :root)

    {node, {:ok, new_acc}}
  end

  # Add inherit conditions with comma instead of brackets
  defp postwalk(
         node = {{:atom, "condition"}, _, [{{:atom, "inherit"}, _, nil}, conditions]},
         {:ok, acc}
       ) do
    new_acc =
      acc
      |> Map.update!(
        :contract,
        &Contract.add_condition(&1, :inherit, aggregate_inherit_conditions(conditions))
      )
      |> Map.put(:scope, :root)

    {node, {:ok, new_acc}}
  end

  defp postwalk(
         node = {{:atom, "condition"}, _, [[{{:atom, "transaction"}, conditions}]]},
         {:ok, acc}
       ) do
    conditions =
      inject_bindings_and_functions(conditions,
        bindings: Enum.map(@transaction_fields, &{&1, ""}) |> Enum.into(%{})
      )

    new_acc =
      acc
      |> Map.update!(:contract, &Contract.add_condition(&1, :transaction, conditions))
      |> Map.put(:scope, :root)

    {node, {:ok, new_acc}}
  end

  defp postwalk(
         node =
           {{:atom, "condition"}, _, [{{:atom, "transaction"}, [line: _], _}, [do: conditions]]},
         {:ok, acc}
       ) do
    conditions =
      inject_bindings_and_functions(conditions,
        bindings: Enum.map(@transaction_fields, &{&1, ""}) |> Enum.into(%{})
      )

    new_acc =
      acc
      |> Map.update!(:contract, &Contract.add_condition(&1, :transaction, conditions))
      |> Map.put(:scope, :root)

    {node, {:ok, new_acc}}
  end

  defp postwalk(
         node = {{:atom, "condition"}, _, [[{{:atom, "oracle"}, conditions}]]},
         {:ok, acc}
       ) do
    conditions = inject_bindings_and_functions(conditions, subject: "data")

    new_acc =
      acc
      |> Map.update!(:contract, &Contract.add_condition(&1, :oracle, conditions))
      |> Map.put(:scope, :root)

    {node, {:ok, new_acc}}
  end

  defp postwalk(node = {{:atom, _}, _, _}, {:ok, acc = %{scope: {:function, _, scope}}}) do
    {node, {:ok, %{acc | scope: scope}}}
  end

  # Convert Access key string to binary
  defp postwalk(
         {{:., meta1, [Access, :get]}, meta2,
          [{{:., meta3, [{subject, meta4, nil}, {:atom, field}]}, meta5, []}, {:atom, key}]},
         acc
       ) do
    {
      {{:., meta1, [Access, :get]}, meta2,
       [
         {{:., meta3, [{subject, meta4, nil}, String.to_existing_atom(field)]}, meta5, []},
         Base.decode16!(key, case: :mixed)
       ]},
      acc
    }
  end

  # Convert map key to binary
  defp postwalk({:%{}, meta, params}, acc = {:ok, %{scope: {:condition, :inherit}}}) do
    encoded_params =
      Enum.map(params, fn
        {{:atom, key}, value} when is_binary(key) ->
          case Base.decode16(key, case: :mixed) do
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

  defp postwalk(node, acc), do: {node, acc}

  defp valid_trigger_opts("datetime", [{{:atom, "at"}, timestamp}]) do
    if length(Integer.digits(timestamp)) != 10 do
      {:error, "invalid datetime"}
    else
      case DateTime.from_unix(timestamp) do
        {:ok, _} ->
          :ok

        _ ->
          {:error, "invalid datetime"}
      end
    end
  end

  defp valid_trigger_opts("interval", [{{:atom, "at"}, interval}]) do
    case CronParser.parse(interval) do
      {:ok, _} ->
        :ok

      {:error, _} ->
        {:error, "invalid interval"}
    end
  end

  defp valid_trigger_opts("transaction", []), do: :ok
  defp valid_trigger_opts("oracle", []), do: :ok

  defp valid_trigger_opts(_, _), do: {:error, "unexpected token"}

  @doc """

  ## Examples

      iex> Interpreter.execute_actions(%Contract{
      ...>   triggers: [
      ...>     %Contract.Trigger{
      ...>       type: :transaction,
      ...>       actions: {:=, [line: 2],
      ...>          [
      ...>            {:scope, [line: 2], nil},
      ...>            {:update_in, [line: 2],
      ...>             [
      ...>               {:scope, [line: 2], nil},
      ...>               ["contract"],
      ...>               {:&, [line: 2],
      ...>                [
      ...>                  {{:., [line: 2],
      ...>                    [
      ...>                      {:__aliases__,
      ...>                       [alias: Uniris.Contracts.Interpreter.TransactionStatements],
      ...>                       [:TransactionStatements]},
      ...>                      :set_type
      ...>                    ]}, [line: 2], [{:&, [line: 2], [1]}, "transfer"]}
      ...>                ]}
      ...>             ]}
      ...>          ]}
      ...>     }
      ...>   ]
      ...> }, :transaction)
      %Contract{
        triggers: [
         %Trigger{actions: {
            :=,
            [{:line, 2}],
            [
              {:scope, [{:line, 2}], nil},
              {:update_in, [line: 2], [{:scope, [line: 2], nil}, ["contract"], {:&, [line: 2], [{{:., [line: 2], [{:__aliases__, [alias: Uniris.Contracts.Interpreter.TransactionStatements], [:TransactionStatements]}, :set_type]}, [line: 2], [{:&, [line: 2], [1]}, "transfer"]}]}]}
            ]
          },
          opts: [],
          type: :transaction}
        ],
        next_transaction: %Transaction{type: :transfer, data: %TransactionData{}}
      }

      iex> Interpreter.execute_actions(%Contract{
      ...>   triggers: [
      ...>     %Contract.Trigger{
      ...>       type: :transaction,
      ...>       actions: {:__block__, [], [
      ...>        {
      ...>          :=,
      ...>          [{:line, 2}],
      ...>          [
      ...>            {:scope, [{:line, 2}], nil},
      ...>            {:update_in, [line: 2], [
      ...>              {:scope, [line: 2], nil},
      ...>              ["contract"],
      ...>              {:&, [line: 2], [
      ...>                {{:., [line: 2], [{:__aliases__, [alias: Uniris.Contracts.Interpreter.TransactionStatements], [:TransactionStatements]}, :set_type]},
      ...>                [line: 2],
      ...>                [{:&, [line: 2], [1]}, "transfer"]}]
      ...>              }
      ...>            ]}
      ...>          ]
      ...>        },
      ...>        {
      ...>          :=,
      ...>          [line: 3],
      ...>          [
      ...>            {:scope, [line: 3], nil},
      ...>            {:update_in, [line: 3], [
      ...>              {:scope, [line: 3], nil},
      ...>              ["contract"],
      ...>              {:&, [line: 3], [
      ...>                {{:., [line: 3], [{:__aliases__, [alias: Uniris.Contracts.Interpreter.TransactionStatements], [:TransactionStatements]}, :add_uco_transfer]},
      ...>                [line: 3], [{:&, [line: 3], [1]},
      ...>                [{"to", {{:., [line: 3], [{:__aliases__, [alias: Uniris.Contracts.Interpreter.Library], [:Library]}, :hash]}, [line: 3], ["@Alice2"]}}, {"amount", 10.04}]]}
      ...>              ]}
      ...>            ]}
      ...>          ]
      ...>        }
      ...>      ]},
      ...>  }]}, :transaction)
      %Contract{
        triggers: [
          %Trigger{
            actions: {:__block__, [], [
              {
                :=,
                [{:line, 2}],
                [
                  {:scope, [{:line, 2}], nil},
                  {:update_in, [line: 2], [
                    {:scope, [line: 2], nil},
                    ["contract"],
                    {:&, [line: 2], [
                      {{:., [line: 2], [{:__aliases__, [alias: Uniris.Contracts.Interpreter.TransactionStatements], [:TransactionStatements]}, :set_type]},
                      [line: 2],
                      [{:&, [line: 2], [1]}, "transfer"]}]
                    }
                  ]}
                ]
              },
              {
                :=,
                [line: 3],
                [
                  {:scope, [line: 3], nil},
                  {:update_in, [line: 3], [
                    {:scope, [line: 3], nil},
                    ["contract"],
                    {:&, [line: 3], [
                      {{:., [line: 3], [{:__aliases__, [alias: Uniris.Contracts.Interpreter.TransactionStatements], [:TransactionStatements]}, :add_uco_transfer]},
                      [line: 3], [{:&, [line: 3], [1]},
                      [{"to", {{:., [line: 3], [{:__aliases__, [alias: Uniris.Contracts.Interpreter.Library], [:Library]}, :hash]}, [line: 3], ["@Alice2"]}}, {"amount", 10.04}]]}
                    ]}
                  ]}
                ]
              }
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
  def execute_actions(contract = %Contract{triggers: triggers}, trigger_type, constants \\ %{}) do
    %Contract.Trigger{actions: quoted_code} = Enum.find(triggers, &(&1.type == trigger_type))

    {%{"contract" => contract}, _} =
      Code.eval_quoted(quoted_code, scope: Map.put(constants, "contract", contract))

    contract
  end

  @doc """
  Execute abritary code using some constants as bindings

  ## Examples

        iex> Interpreter.execute({{:., [line: 1],
        ...> [
        ...>   {:__aliases__, [alias: Uniris.Contracts.Interpreter.Library],
        ...>    [:Library]},
        ...>   :regex_match?
        ...> ]}, [line: 1],
        ...> [{:get_in, [line: 1], [{:scope, [line: 1], nil}, ["content"]]}, "abc"]}, %{ "content" => "abc"})
        true

        iex> Interpreter.execute({:==, [],
        ...> [
        ...>   {:get_in, [line: 1], [{:scope, [line: 1], nil}, ["next_transaction", "content"]]},
        ...>   {:get_in, [line: 1], [{:scope, [line: 1], nil}, ["previous_transaction", "content"]]},
        ...> ]}, %{ "previous_transaction" => %{"content" => "abc"}, "next_transaction" => %{ "content" => "abc" } })
        true

        iex> Interpreter.execute({{:., [line: 2],
        ...> [
        ...>    {:__aliases__, [alias: Uniris.Contracts.Interpreter.Library],
        ...>     [:Library]},
        ...>    :hash
        ...>  ]}, [line: 2],
        ...> [{:get_in, [line: 2], [{:scope, [line: 2], nil}, ["content"]]}]}, %{ "content" => "abc" })
        <<0, 186, 120, 22, 191, 143, 1, 207, 234, 65, 65, 64, 222, 93, 174, 34, 35, 176, 3, 97, 163, 150, 23, 122, 156, 180, 16, 255, 97, 242, 0, 21, 173>>
  """
  def execute(quoted_code, constants = %{}) do
    {res, _} = Code.eval_quoted(quoted_code, scope: constants)
    res
  end

  defp inject_bindings_and_functions(quoted_code, opts) when is_list(opts) do
    bindings = Keyword.get(opts, :bindings, %{})
    subject = Keyword.get(opts, :subject)

    {ast, _} =
      Macro.postwalk(
        quoted_code,
        %{
          bindings: bindings,
          library_functions: @library_functions_names,
          transaction_statements_functions: @transaction_statements_functions_names,
          subject: subject
        },
        &do_postwalk_execution/2
      )

    ast
  end

  defp do_postwalk_execution({:=, metadata, [var_name, content]}, acc) do
    put_ast =
      {{:., metadata, [{:__aliases__, metadata, [:Map]}, :put]}, metadata,
       [{:scope, metadata, nil}, var_name, parse_value(content)]}

    {
      {:=, metadata, [{:scope, metadata, nil}, put_ast]},
      put_in(acc, [:bindings, var_name], parse_value(content))
    }
  end

  defp do_postwalk_execution(_node = {{:atom, atom}, metadata, args}, acc = %{subject: nil})
       when atom in @library_functions_names do
    {{{:., metadata, [{:__aliases__, [alias: Library], [:Library]}, String.to_atom(atom)]},
      metadata, args}, acc}
  end

  defp do_postwalk_execution(_node = {{:atom, atom}, metadata, args}, acc = %{subject: subject})
       when atom in @library_functions_names do
    subject_args =
      if is_list(subject) do
        subject
      else
        [subject]
      end

    {{{:., metadata, [{:__aliases__, [alias: Library], [:Library]}, String.to_atom(atom)]},
      metadata, [{:get_in, metadata, [{:scope, metadata, nil}, subject_args]} | args || []]}, acc}
  end

  defp do_postwalk_execution(_node = {{:atom, atom}, metadata, args}, acc)
       when atom in @transaction_statements_functions_names do
    args =
      Enum.map(args, fn arg ->
        {ast, _} = Macro.postwalk(arg, acc, &do_postwalk_execution/2)
        ast
      end)

    ast = {
      {:., metadata,
       [
         {:__aliases__, [alias: TransactionStatements], [:TransactionStatements]},
         String.to_atom(atom)
       ]},
      metadata,
      [{:&, metadata, [1]} | args]
    }

    update_ast =
      {:update_in, metadata,
       [
         {:scope, metadata, nil},
         ["contract"],
         {:&, metadata,
          [
            ast
          ]}
       ]}

    {
      {:=, metadata, [{:scope, metadata, nil}, update_ast]},
      acc
    }
  end

  defp do_postwalk_execution(
         _node = {{:atom, atom}, metadata, _args},
         acc = %{bindings: bindings}
       ) do
    if Map.has_key?(bindings, atom) do
      {
        {:get_in, metadata, [{:scope, metadata, nil}, [atom]]},
        acc
      }
    else
      {atom, acc}
    end
  end

  defp do_postwalk_execution({:., metadata, [parent, {{:atom, field}}]}, acc) do
    {
      {:get_in, metadata, [{:scope, metadata, nil}, [parent, parse_value(field)]]},
      acc
    }
  end

  defp do_postwalk_execution(
         {:., _, [{:get_in, metadata, [{:scope, _, nil}, access]}, {:atom, field}]},
         acc
       ) do
    {
      {:get_in, metadata, [{:scope, metadata, nil}, access ++ [parse_value(field)]]},
      acc
    }
  end

  defp do_postwalk_execution(
         {:., metadata,
          [{:get_in, metadata, [{:scope, metadata, nil}, [parent]]}, {:atom, child}]},
         acc
       ) do
    {{:get_in, metadata, [{:scope, metadata, nil}, [parent, parse_value(child)]]}, acc}
  end

  defp do_postwalk_execution({{:atom, atom}, val}, acc) do
    {ast, _} = Macro.postwalk(val, acc, &do_postwalk_execution/2)
    {{atom, ast}, acc}
  end

  defp do_postwalk_execution({{:get_in, metadata, [{:scope, metadata, nil}, access]}, _, []}, acc) do
    {
      {:get_in, metadata, [{:scope, metadata, nil}, access]},
      acc
    }
  end

  defp do_postwalk_execution({:==, _, [{left, _, args_l}, {right, _, args_r}]}, acc) do
    {{:==, [], [{left, [], args_l}, {right, [], args_r}]}, acc}
  end

  defp do_postwalk_execution({:==, _, [{left, _, args}, right]}, acc) do
    {{:==, [], [{left, [], args}, right]}, acc}
  end

  defp do_postwalk_execution({node, _, _}, acc) when is_binary(node) do
    {parse_value(node), acc}
  end

  defp do_postwalk_execution(node, acc), do: {parse_value(node), acc}

  defp aggregate_inherit_conditions(conditions) do
    default_conditions =
      Enum.map(@inherit_fields, fn key ->
        {key,
         {:==, [line: 0],
          [
            {:get_in, [line: 0], [{:scope, [line: 0], nil}, ["next", key]]},
            {:get_in, [line: 0], [{:scope, [line: 0], nil}, ["prev", key]]}
          ]}}
      end)
      |> Enum.into(%{})

    conditions =
      Enum.map(conditions, fn {{:atom, subject}, condition} ->
        case inject_bindings_and_functions(condition, subject: ["next", subject]) do
          {op, metadata, args} ->
            {subject,
             {:==, metadata,
              [
                {op, metadata, args},
                {:get_in, metadata, [{:scope, metadata, nil}, ["next", subject]]}
              ]}}

          val ->
            {subject, {:==, [], [val, {:get_in, [], [{:scope, [], nil}, ["next", subject]]}]}}
        end
      end)

    default_conditions
    |> Map.merge(Enum.into(conditions, %{}))
    |> Enum.reduce(nil, fn
      {_, ast}, nil ->
        ast

      {_, ast}, prev_ast = {:and, metadata, _} ->
        {:and, metadata,
         [
           prev_ast,
           ast
         ]}

      {_, ast}, prev_ast = {_, metadata, _} ->
        {:and, metadata,
         [
           prev_ast,
           ast
         ]}
    end)
  end

  defp parse_value(val) when is_binary(val) do
    case Base.decode16(val) do
      {:ok, bin} ->
        bin

      _ ->
        val
    end
  end

  defp parse_value(val), do: val
end
