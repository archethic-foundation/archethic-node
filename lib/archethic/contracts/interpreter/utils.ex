defmodule Archethic.Contracts.Interpreter.Utils do
  @moduledoc false

  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.Contracts.Interpreter.TransactionStatements

  @library_functions_names Library.__info__(:functions)
                           |> Enum.map(&Atom.to_string(elem(&1, 0)))

  @library_functions_names_atoms Library.__info__(:functions)
                                 |> Enum.map(&{Atom.to_string(elem(&1, 0)), elem(&1, 0)})
                                 |> Enum.into(%{})

  @transaction_statements_functions_names TransactionStatements.__info__(:functions)
                                          |> Enum.map(&Atom.to_string(elem(&1, 0)))

  @transaction_statements_functions_names_atoms TransactionStatements.__info__(:functions)
                                                |> Enum.map(
                                                  &{Atom.to_string(elem(&1, 0)), elem(&1, 0)}
                                                )
                                                |> Enum.into(%{})

  @supported_hash Archethic.Crypto.list_supported_hash_functions(:string)

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
    "token_ledger",
    "uco_transfers",
    "token_transfers",
    "authorized_public_keys",
    "secrets",
    "recipients"
  ]

  @spec transaction_fields() :: list(String.t())
  def transaction_fields, do: @transaction_fields

  @spec prewalk(Macro.t(), any()) :: {Macro.t(), any()}
  def prewalk(node = :atom, acc), do: {node, acc}
  def prewalk(node = {:atom, key}, acc) when is_binary(key), do: {node, acc}

  def prewalk(node = {{:atom, key}, _, nil}, acc = {:ok, _}) when is_binary(key),
    do: {node, acc}

  def prewalk(node, acc) when is_list(node), do: {node, acc}

  # Whitelist operators
  def prewalk(node = {:+, _, _}, acc = {:ok, %{scope: scope}}) when scope != :root,
    do: {node, acc}

  def prewalk(node = {:-, _, _}, acc = {:ok, %{scope: scope}}) when scope != :root,
    do: {node, acc}

  def prewalk(node = {:/, _, _}, acc = {:ok, %{scope: scope}}) when scope != :root,
    do: {node, acc}

  def prewalk(node = {:*, _, _}, acc = {:ok, %{scope: scope}}) when scope != :root,
    do: {node, acc}

  def prewalk(node = {:>, _, _}, acc = {:ok, %{scope: scope}}) when scope != :root,
    do: {node, acc}

  def prewalk(node = {:<, _, _}, acc = {:ok, %{scope: scope}}) when scope != :root,
    do: {node, acc}

  def prewalk(node = {:>=, _, _}, acc = {:ok, %{scope: scope}}) when scope != :root,
    do: {node, acc}

  def prewalk(node = {:<=, _, _}, acc = {:ok, %{scope: scope}}) when scope != :root,
    do: {node, acc}

  def prewalk(node = {:|>, _, _}, acc = {:ok, %{scope: scope}}) when scope != :root,
    do: {node, acc}

  def prewalk(node = {:==, _, _}, acc = {:ok, %{scope: scope}}) when scope != :root,
    do: {node, acc}

  # Whitelist the use of doted statement
  def prewalk(node = {{:., _, [{_, _, _}, _]}, _, []}, acc = {:ok, %{scope: scope}})
      when scope != :root,
      do: {node, acc}

  def prewalk(node = {:if, _, _}, acc = {:ok, %{scope: scope}}) when scope != :root,
    do: {node, acc}

  def prewalk(node = {:else, _}, acc = {:ok, %{scope: scope}}) when scope != :root,
    do: {node, acc}

  def prewalk(node = [do: _, else: _], acc = {:ok, %{scope: scope}}) when scope != :root,
    do: {node, acc}

  def prewalk(node = :else, acc = {:ok, %{scope: scope}}) when scope != :root, do: {node, acc}

  def prewalk(node = {:and, _, _}, acc = {:ok, _}), do: {node, acc}
  def prewalk(node = {:or, _, _}, acc = {:ok, _}), do: {node, acc}

  # Whitelist the in operation
  def prewalk(node = {:in, _, [_, _]}, acc = {:ok, _}), do: {node, acc}

  # Whitelist maps
  def prewalk(node = {:%{}, _, fields}, acc = {:ok, _}) when is_list(fields), do: {node, acc}

  def prewalk(node = {key, _val}, acc) when is_binary(key) do
    {node, acc}
  end

  # Whitelist the multiline
  def prewalk(node = {{:__block__, _, _}}, acc = {:ok, _}) do
    {node, acc}
  end

  def prewalk(node = {:__block__, _, _}, acc = {:ok, _}) do
    {node, acc}
  end

  # Whitelist interpolation of strings
  def prewalk(
        node =
          {:<<>>, _, [{:"::", _, [{{:., _, [Kernel, :to_string]}, _, _}, {:binary, _, nil}]}, _]},
        acc
      ) do
    {node, acc}
  end

  def prewalk(
        node =
          {:<<>>, _,
           [
             _,
             {:"::", _, [{{:., _, [Kernel, :to_string]}, _, _}, _]}
           ]},
        acc
      ) do
    {node, acc}
  end

  def prewalk(node = {:"::", _, [{{:., _, [Kernel, :to_string]}, _, _}, _]}, acc) do
    {node, acc}
  end

  def prewalk(node = {{:., _, [Kernel, :to_string]}, _, _}, acc) do
    {node, acc}
  end

  def prewalk(node = {:., _, [Kernel, :to_string]}, acc) do
    {node, acc}
  end

  def prewalk(node = Kernel, acc), do: {node, acc}
  def prewalk(node = :to_string, acc), do: {node, acc}
  def prewalk(node = {:binary, _, nil}, acc), do: {node, acc}

  # Whitelist generics
  def prewalk(true, acc = {:ok, _}), do: {true, acc}
  def prewalk(false, acc = {:ok, _}), do: {false, acc}
  def prewalk(number, acc = {:ok, _}) when is_number(number), do: {number, acc}
  def prewalk(string, acc = {:ok, _}) when is_binary(string), do: {string, acc}
  def prewalk(node = [do: _], acc = {:ok, _}), do: {node, acc}
  def prewalk(node = {:do, _}, acc = {:ok, _}), do: {node, acc}
  def prewalk(node = :do, acc = {:ok, _}), do: {node, acc}

  # Whitelist the use of list
  def prewalk(node = [{{:atom, _}, _, nil} | _], acc = {:ok, %{scope: scope}})
      when scope != :root do
    {node, acc}
  end

  # Whitelist access to map field
  def prewalk(
        node = {{:., _, [Access, :get]}, _, _},
        acc = {:ok, %{scope: scope}}
      )
      when scope != :root do
    {node, acc}
  end

  def prewalk(node = {:., _, [Access, :get]}, acc = {:ok, %{scope: scope}}) when scope != :root,
    do: {node, acc}

  def prewalk(node = Access, acc), do: {node, acc}
  def prewalk(node = :get, acc), do: {node, acc}

  # Whitelist the usage of transaction fields in references: "transaction/contract/previous/next"
  def prewalk(
        node = {:., _, [{{:atom, transaction_ref}, _, nil}, {:atom, transaction_field}]},
        acc = {:ok, %{scope: scope}}
      )
      when scope != :root and transaction_ref in ["next", "previous", "transaction", "contract"] and
             transaction_field in @transaction_fields do
    {node, acc}
  end

  def prewalk(
        node = {{:atom, _}, {{:., _, [{{:atom, transaction_ref}, _, nil}, {:atom, type}]}, _, _}},
        acc
      )
      when transaction_ref in ["next", "previous", "transaction", "contract"] and
             type in @transaction_fields do
    {node, acc}
  end

  # Whitelist the in?/2 function
  def prewalk(
        node = {{:atom, "in?"}, _, [_, _]},
        acc = {:ok, %{scope: scope}}
      )
      when scope != :root do
    {node, acc}
  end

  # Whitelist the head/1 function
  def prewalk(
        node = {{:atom, "head"}, _, [_]},
        acc = {:ok, %{scope: scope}}
      )
      when scope != :root do
    {node, acc}
  end

  # Whitelist the size/1 library function
  def prewalk(
        node = {{:atom, "size"}, _, [_data]},
        acc = {:ok, %{scope: scope}}
      )
      when scope != :root do
    {node, acc}
  end

  # Whitelist the append/2 library function
  def prewalk(
        node = {{:atom, "append"}, _, [_, _]},
        acc = {:ok, %{scope: scope}}
      )
      when scope != :root do
    {node, acc}
  end

  # Whitelist the prepend/2 library function
  def prewalk(
        node = {{:atom, "prepend"}, _, [_, _]},
        acc = {:ok, %{scope: scope}}
      )
      when scope != :root do
    {node, acc}
  end

  # Whitelist the concat/2 library function
  def prewalk(
        node = {{:atom, "concat"}, _, [_, _]},
        acc = {:ok, %{scope: scope}}
      )
      when scope != :root do
    {node, acc}
  end

  # Whitelist the set/3 library function
  def prewalk(
        node = {{:atom, "set"}, _, [_, _, _]},
        acc = {:ok, %{scope: scope}}
      )
      when scope != :root do
    {node, acc}
  end

  # Whitelist and delegate the rem/2 function to Kernel
  def prewalk(
        _node = {{:atom, "rem"}, meta, ctx = [_, _]},
        acc = {:ok, %{scope: scope}}
      )
      when scope != :root do
    {{:rem, Keyword.put(meta, :context, Kernel), ctx}, acc}
  end

  # Whitelist the hash/1 function
  def prewalk(node = {{:atom, "hash"}, _, [_data]}, acc = {:ok, %{scope: scope}})
      when scope != :root,
      do: {node, acc}

  # Whitelist the hash/2 function
  def prewalk(node = {{:atom, "hash"}, _, [_data, algo]}, acc = {:ok, %{scope: scope}})
      when scope != :root and algo in @supported_hash,
      do: {node, acc}

  # Whitelist the regex_match?/2 function
  def prewalk(
        node = {{:atom, "regex_match?"}, _, [_input, _search]},
        acc = {:ok, %{scope: scope}}
      )
      when scope != :root,
      do: {node, acc}

  # Whitelist the regex_extract/2 function
  def prewalk(
        node = {{:atom, "regex_extract"}, _, [_input, _search]},
        acc = {:ok, %{scope: scope}}
      )
      when scope != :root,
      do: {node, acc}

  # Whitelist the regex_scan/2 function
  def prewalk(
        node = {{:atom, "regex_scan"}, _, [_input, _search]},
        acc = {:ok, %{scope: scope}}
      )
      when scope != :root,
      do: {node, acc}

  # Whitelist the regex_replace/2 function
  def prewalk(
        node = {{:atom, "regex_replace"}, _, [_input, _search, _replacement]},
        acc = {:ok, %{scope: scope}}
      )
      when scope != :root,
      do: {node, acc}

  # Whitelist the json_path_extract/2 function
  def prewalk(
        node = {{:atom, "json_path_extract"}, _, [_input, _search]},
        acc = {:ok, %{scope: scope}}
      )
      when scope != :root,
      do: {node, acc}

  # Whitelist the json_path_match?/2 function
  def prewalk(
        node = {{:atom, "json_path_match?"}, _, [_input, _search]},
        acc = {:ok, %{scope: scope}}
      )
      when scope != :root,
      do: {node, acc}

  # Whitelist the get_genesis_address/1 function
  def prewalk(
        node = {{:atom, "get_genesis_address"}, _, [_address]},
        acc = {:ok, %{scope: scope}}
      )
      when scope != :root do
    {node, acc}
  end

  # Whitelist the get_genesis_public_key/1 function
  def prewalk(
        node = {{:atom, "get_genesis_public_key"}, _, [_address]},
        acc = {:ok, %{scope: scope}}
      )
      when scope != :root do
    {node, acc}
  end

  # Whitelist the timestamp/0 function in condition
  def prewalk(node = {{:atom, "timestamp"}, _, _}, acc = {:ok, %{scope: scope}})
      when scope != :root do
    {node, acc}
  end

  # Blacklist everything else
  def prewalk(node, _acc) do
    throw({:error, node})
  end

  @spec postwalk(Macro.t(), any()) :: {Macro.t(), any()}
  def postwalk(node = {{:atom, fun}, _, _}, {:ok, context = %{scope: {:function, _, scope}}})
      when fun in @library_functions_names or fun in @transaction_statements_functions_names do
    {node, {:ok, %{context | scope: scope}}}
  end

  def postwalk(
        {{:., meta1, [Access, :get]}, meta2,
         [{{:., meta3, [{subject, meta4, nil}, {:atom, field}]}, meta5, []}, {:atom, key}]},
        acc = {:ok, _}
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
  def postwalk({:%{}, meta, params}, acc = {:ok, _}) do
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

  def postwalk(node, acc) when is_binary(node) do
    if String.printable?(node) do
      case Base.decode16(node, case: :mixed) do
        {:ok, hex} ->
          {Base.encode16(hex), acc}

        _ ->
          {node, acc}
      end
    else
      {node, acc}
    end
  end

  def postwalk(node, acc), do: {node, acc}

  @doc """
  Inject context variables and functions by transforming the ast
  """
  @spec inject_bindings_and_functions(Macro.t(), list()) :: Macro.t()
  def inject_bindings_and_functions(quoted_code, opts) when is_list(opts) do
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
       [{:scope, metadata, nil}, var_name, content]}

    {
      {:=, metadata, [{:scope, metadata, nil}, put_ast]},
      put_in(acc, [:bindings, var_name], content)
    }
  end

  defp do_postwalk_execution(_node = {{:atom, atom}, metadata, args}, acc)
       when atom in @library_functions_names do
    fun = Map.get(@library_functions_names_atoms, atom)

    {{{:., metadata, [{:__aliases__, [alias: Library], [:Library]}, fun]}, metadata, args}, acc}
  end

  defp do_postwalk_execution(_node = {{:atom, atom}, metadata, args}, acc)
       when atom in @transaction_statements_functions_names do
    args =
      Enum.map(args, fn arg ->
        {ast, _} = Macro.postwalk(arg, acc, &do_postwalk_execution/2)
        ast
      end)

    fun = Map.get(@transaction_statements_functions_names_atoms, atom)

    ast = {
      {:., metadata,
       [
         {:__aliases__, [alias: TransactionStatements], [:TransactionStatements]},
         fun
       ]},
      metadata,
      [{:&, metadata, [1]} | args]
    }

    update_ast =
      {:update_in, metadata,
       [
         {:scope, metadata, nil},
         ["next_transaction"],
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
         acc = %{bindings: bindings, subject: subject}
       ) do
    if Map.has_key?(bindings, atom) do
      search =
        case subject do
          nil ->
            [atom]

          subject ->
            # Do not use the subject when using reserved keyword
            if atom in ["contract", "transaction", "next", "previous"] do
              [atom]
            else
              [subject, atom]
            end
        end

      {
        {:get_in, metadata, [{:scope, metadata, nil}, search]},
        acc
      }
    else
      {atom, acc}
    end
  end

  defp do_postwalk_execution({:., metadata, [parent, {{:atom, field}}]}, acc) do
    {
      {:get_in, metadata, [{:scope, metadata, nil}, [parent, field]]},
      acc
    }
  end

  defp do_postwalk_execution(
         {:., _, [{:get_in, metadata, [{:scope, _, nil}, access]}, {:atom, field}]},
         acc
       ) do
    {
      {:get_in, metadata, [{:scope, metadata, nil}, access ++ [field]]},
      acc
    }
  end

  defp do_postwalk_execution(
         {:., metadata,
          [{:get_in, metadata, [{:scope, metadata, nil}, [parent]]}, {:atom, child}]},
         acc
       ) do
    {{:get_in, metadata, [{:scope, metadata, nil}, [parent, child]]}, acc}
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
    {node, acc}
  end

  defp do_postwalk_execution(node, acc), do: {node, acc}

  @doc """
  Format an error message from the failing ast node

  It returns message with metadata if possible to indicate the line of the error
  """
  @spec format_error_reason(any(), String.t()) :: String.t()
  def format_error_reason({:atom, _key}, reason) do
    do_format_error_reason(reason, "", [])
  end

  def format_error_reason({{:atom, key}, metadata, _}, reason) do
    do_format_error_reason(reason, key, metadata)
  end

  def format_error_reason({_, metadata, [{:__aliases__, _, [atom: module]} | _]}, reason) do
    do_format_error_reason(reason, module, metadata)
  end

  def format_error_reason(ast_node = {_, metadata, _}, reason) do
    do_format_error_reason(reason, Macro.to_string(ast_node), metadata)
  end

  def format_error_reason({{:atom, _}, {_, metadata, _}}, reason) do
    do_format_error_reason(reason, "", metadata)
  end

  def format_error_reason({{:atom, key}, _}, reason) do
    do_format_error_reason(reason, key, [])
  end

  defp do_format_error_reason(message, cause, metadata) do
    message = prepare_message(message)

    [prepare_message(message), cause, metadata_to_string(metadata)]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" - ")
  end

  defp prepare_message(message) when is_atom(message) do
    message |> Atom.to_string() |> String.replace("_", " ")
  end

  defp prepare_message(message) when is_binary(message) do
    String.trim_trailing(message, ":")
  end

  defp metadata_to_string(line: line, column: column), do: "L#{line}:C#{column}"
  defp metadata_to_string(line: line), do: "L#{line}"
  defp metadata_to_string(_), do: ""
end
