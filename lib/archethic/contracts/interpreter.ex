defmodule Archethic.Contracts.Interpreter do
  @moduledoc false

  require Logger

  alias __MODULE__.Legacy
  alias __MODULE__.ActionInterpreter
  alias __MODULE__.ConditionInterpreter
  alias __MODULE__.FunctionInterpreter

  alias __MODULE__.ConditionValidator

  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.ContractConditions, as: Conditions
  alias Archethic.Contracts.ContractConstants, as: Constants

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData.Recipient

  alias Archethic.Utils

  @type version() :: integer()
  @type execute_opts :: [time_now: DateTime.t()]
  @type function_key() :: {String.t(), integer()}

  @doc """
  Dispatch through the correct interpreter.
  This return a filled contract structure or an human-readable error.
  """
  @spec parse(code :: binary()) :: {:ok, Contract.t()} | {:error, String.t()}
  def parse(""), do: {:error, "Not a contract"}

  def parse(code) when is_binary(code) do
    start = System.monotonic_time()

    result =
      case sanitize_code(code) do
        {:ok, block} ->
          case block do
            {:__block__, [], [{:@, _, [{{:atom, "version"}, _, [version]}]} | rest]} ->
              parse_contract(version, rest)
              |> check_contract_blocks()

            _ ->
              Legacy.parse(block)
              |> check_contract_blocks()
          end

        {:error, :invalid_syntax} ->
          {:error, "Parse error: invalid language syntax"}

        {:error, {[line: line, column: column], _msg_info, _token}} ->
          {:error, "Parse error at line #{line} column #{column}"}
      end

    :telemetry.execute([:archethic, :contract, :parsing], %{
      duration: System.monotonic_time() - start
    })

    result
  end

  @doc """
  Sanitize code takes care of converting atom to {:atom, bin()}.
  This way the user cannot create atoms at all. (which is mandatory to avoid atoms-table exhaustion)
  """
  @spec sanitize_code(binary(), list()) :: {:ok, Macro.t()} | {:error, any()}
  def sanitize_code(code, opts \\ []) when is_binary(code) do
    ignore_meta? = Keyword.get(opts, :ignore_meta?, false)

    opts = [static_atoms_encoder: &atom_encoder/2]
    charlist_code = code |> String.to_charlist()

    case :elixir.string_to_tokens(charlist_code, 1, 1, "nofile", opts) do
      {:ok, tokens} ->
        transform_tokens(tokens, ignore_meta?) |> :elixir.tokens_to_quoted("nofile", opts)

      error ->
        error
    end
  rescue
    _ -> {:error, :invalid_syntax}
  end

  defp transform_tokens(tokens, ignore_meta?) do
    Enum.map(tokens, fn
      # Transform 0x to hex
      {:int, {line, column, _}, [?0, ?x | hex]} ->
        string_hex = hex |> List.to_string() |> String.upcase()
        meta = if ignore_meta?, do: {0, 0, nil}, else: {line, column, nil}

        {:bin_string, meta, [string_hex]}

      token ->
        if ignore_meta? do
          {_line, _colum, last} = elem(token, 1)
          token |> Tuple.delete_at(1) |> Tuple.insert_at(1, {0, 0, last})
        else
          token
        end
    end)
  end

  @doc """
  Return true if the given conditions are valid on the given constants
  """
  @spec valid_conditions?(version(), Conditions.t(), map()) :: bool()
  def valid_conditions?(0, conditions, constants) do
    Legacy.valid_conditions?(conditions, constants)
  end

  def valid_conditions?(1, conditions, constants) do
    ConditionValidator.valid_conditions?(conditions, constants)
  end

  @doc """
  Execution the given contract's trig
  /!\ The transaction returned is not complete, only the `type` and `data` are filled-in.
  """
  @spec execute_trigger(
          Contract.trigger_type(),
          Contract.t(),
          nil | Transaction.t(),
          nil | Recipient.t(),
          execute_opts()
        ) ::
          {:ok, nil | Transaction.t()}
          | {:error, :contract_failure | :invalid_triggers_execution}
  def execute_trigger(
        trigger_type,
        %Contract{
          version: version,
          triggers: triggers,
          constants: %Constants{contract: contract_constants},
          functions: functions
        },
        maybe_trigger_tx,
        maybe_recipient,
        opts \\ []
      ) do
    case triggers[trigger_type] do
      nil ->
        {:error, :invalid_triggers_execution}

      trigger_code ->
        timestamp_now =
          case Keyword.get(opts, :time_now) do
            nil ->
              # you must use the :time_now opts during the validation workflow
              # because there is no validation_stamp yet
              time_now(trigger_type, maybe_trigger_tx)

            time_now ->
              time_now
          end
          |> DateTime.to_unix()

        named_action_constants = get_named_action_constants(trigger_type, maybe_recipient)

        constants =
          named_action_constants
          |> Map.merge(%{
            "transaction" =>
              case maybe_trigger_tx do
                nil ->
                  nil

                trigger_tx ->
                  # :oracle & :transaction
                  Constants.from_transaction(trigger_tx)
              end,
            "contract" => contract_constants,
            :time_now => timestamp_now,
            :functions => functions
          })

        result =
          case version do
            0 -> Legacy.execute_trigger(trigger_code, constants)
            _ -> ActionInterpreter.execute(trigger_code, constants)
          end

        {:ok, result}
    end
  rescue
    _ ->
      # it's ok to loose the error because it's user-code
      {:error, :contract_failure}
  end

  @doc """
  Execute the given function with the givent constants and arguments
  """
  @spec execute_function(any(), map(), list()) :: result :: any()
  def execute_function(%{ast: ast, args: args_names}, constants, args) do
    FunctionInterpreter.execute(ast, constants, args_names, args)
  end

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

  def format_error_reason(
        {{:., metadata, [{:__aliases__, _, [atom: module_name]}, {:atom, function_name}]}, _,
         args},
        reason
      ) do
    # this cover the following case:
    #
    # code: List.empty?(12)
    # ast:{{:., [line: 4], [{:__aliases__, [line: 4], [atom: "List"]}, {:atom, "empty?"}]}, [line: 4], '\f'}
    #
    # macro.to_string would return this:
    # "{:atom, \"List\"} . :atom => \"empty?\"(12)"
    #
    # this code return this:
    # List.empty?(12)
    args_str = Enum.map_join(args, ", ", &Macro.to_string/1)

    do_format_error_reason(reason, "#{module_name}.#{function_name}(#{args_str})", metadata)
  end

  def format_error_reason(ast_node = {_, metadata, _}, reason) do
    node_msg =
      try do
        Macro.to_string(ast_node)
      rescue
        _ ->
          # {:atom, _} is not an atom so it breaks the Macro.to_string/1
          # here we replace it with :_var_
          {sanified_ast, variables} =
            Macro.traverse(
              ast_node,
              [],
              fn node, acc -> {node, acc} end,
              fn
                {:atom, bin}, acc -> {:_var_, [bin | acc]}
                node, acc -> {node, acc}
              end
            )

          # then we will replace all instances of _var_ in the string with the binary
          variables
          |> Enum.reverse()
          |> Enum.reduce(Macro.to_string(sanified_ast), fn variable, acc ->
            String.replace(acc, "_var_", variable, global: false)
          end)
      end

    do_format_error_reason(reason, node_msg, metadata)
  end

  def format_error_reason({{:atom, _}, {_, metadata, _}}, reason) do
    do_format_error_reason(reason, "", metadata)
  end

  def format_error_reason({{:atom, key}, _}, reason) do
    do_format_error_reason(reason, key, [])
  end

  def format_error_reason(_node, reason) do
    do_format_error_reason(reason, "", [])
  end

  # ------------------------------------------------------------
  #              _            _
  #   _ __  _ __(___   ____ _| |_ ___
  #  | '_ \| '__| \ \ / / _` | __/ _ \
  #  | |_) | |  | |\ V | (_| | ||  __/
  #  | .__/|_|  |_| \_/ \__,_|\__\___|
  #  |_|
  # ------------------------------------------------------------

  # -----------------------------------------
  # format errors
  # -----------------------------------------
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

  # -----------------------------------------
  # parsing
  # -----------------------------------------
  defp atom_encoder(atom, _) do
    if atom in ["if"] do
      {:ok, String.to_atom(atom)}
    else
      {:ok, {:atom, atom}}
    end
  end

  defp parse_contract(1, ast) do
    functions_keys = get_function_keys(ast)

    case parse_ast_block(ast, %Contract{}, functions_keys) do
      {:ok, contract} ->
        {:ok, %{contract | version: 1}}

      {:error, node, reason} ->
        {:error, format_error_reason(node, reason)}
    end
  end

  defp parse_contract(_version, _ast) do
    {:error, "@version not supported"}
  end

  defp parse_ast_block([ast | rest], contract, functions_keys) do
    case parse_ast(ast, contract, functions_keys) do
      {:ok, contract} ->
        parse_ast_block(rest, contract, functions_keys)

      {:error, _, _} = e ->
        e
    end
  end

  defp parse_ast_block([], contract, _), do: {:ok, contract}

  defp parse_ast(ast = {{:atom, "condition"}, _, _}, contract, functions_keys) do
    case ConditionInterpreter.parse(ast, functions_keys) do
      {:ok, condition_type, condition} ->
        {:ok, Contract.add_condition(contract, condition_type, condition)}

      {:error, _, _} = e ->
        e
    end
  end

  defp parse_ast(ast = {{:atom, "actions"}, _, _}, contract, functions_keys) do
    case ActionInterpreter.parse(ast, functions_keys) do
      {:ok, trigger_type, actions} ->
        {:ok, Contract.add_trigger(contract, trigger_type, actions)}

      {:error, _, _} = e ->
        e
    end
  end

  defp parse_ast(
         ast = {{:atom, "export"}, _, [{{:atom, "fun"}, _, _} | _]},
         contract,
         functions_keys
       ) do
    case FunctionInterpreter.parse(ast, functions_keys) do
      {:ok, function_name, args, ast} ->
        {:ok, Contract.add_function(contract, function_name, ast, args, :public)}

      {:error, _, _} = e ->
        e
    end
  end

  defp parse_ast(ast = {{:atom, "fun"}, _, _}, contract, functions_keys) do
    case FunctionInterpreter.parse(ast, functions_keys) do
      {:ok, function_name, args, ast} ->
        {:ok, Contract.add_function(contract, function_name, ast, args, :private)}

      {:error, _, _} = e ->
        e
    end
  end

  defp parse_ast(ast, _, _), do: {:error, ast, "unexpected term"}

  defp time_now({:transaction, _, _}, %Transaction{
         validation_stamp: %ValidationStamp{timestamp: timestamp}
       }) do
    timestamp
  end

  defp time_now(:transaction, %Transaction{
         validation_stamp: %ValidationStamp{timestamp: timestamp}
       }) do
    timestamp
  end

  defp time_now(:oracle, %Transaction{
         validation_stamp: %ValidationStamp{timestamp: timestamp}
       }) do
    timestamp
  end

  defp time_now({:datetime, timestamp}, nil) do
    timestamp
  end

  defp time_now({:interval, interval}, nil) do
    Utils.get_current_time_for_interval(interval)
  end

  defp get_function_keys([{{:atom, "fun"}, _, [{{:atom, function_name}, _, args} | _]} | rest]) do
    [{function_name, length(args), :private} | get_function_keys(rest)]
  end

  defp get_function_keys([
         {{:atom, "export"}, _,
          [{{:atom, "fun"}, _, [{{:atom, function_name}, _, args} | _]} | _]}
         | rest
       ]) do
    [{function_name, length(args), :public} | get_function_keys(rest)]
  end

  defp get_function_keys([_ | rest]), do: get_function_keys(rest)
  defp get_function_keys([]), do: []

  # -----------------------------------------
  # contract validation
  # -----------------------------------------
  defp check_contract_blocks({:error, reason}), do: {:error, reason}

  defp check_contract_blocks(
         {:ok, contract = %Contract{triggers: triggers, conditions: conditions}}
       ) do
    case do_check_contract_blocks(Map.keys(triggers), Map.keys(conditions)) do
      :ok ->
        {:ok, contract}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_check_contract_blocks([], _conditions), do: :ok

  defp do_check_contract_blocks([:oracle | rest], conditions) do
    if :oracle in conditions do
      do_check_contract_blocks(rest, conditions)
    else
      {:error, "missing 'condition oracle' block"}
    end
  end

  defp do_check_contract_blocks([:transaction | rest], conditions) do
    if :transaction in conditions do
      do_check_contract_blocks(rest, conditions)
    else
      {:error, "missing 'condition transaction' block"}
    end
  end

  defp do_check_contract_blocks([{:interval, _} | rest], conditions) do
    do_check_contract_blocks(rest, conditions)
  end

  defp do_check_contract_blocks([{:datetime, _} | rest], conditions) do
    do_check_contract_blocks(rest, conditions)
  end

  defp do_check_contract_blocks([{:transaction, action, args_names} | rest], conditions) do
    if {:transaction, action, args_names} in conditions do
      do_check_contract_blocks(rest, conditions)
    else
      {:error,
       "missing 'condition transaction, on: #{action}(#{Enum.join(args_names, ", ")})' block"}
    end
  end

  defp get_named_action_constants(
         {:transaction, _action, args_names},
         %Recipient{
           args: args_values
         }
       ) do
    args_names
    |> Enum.zip(args_values)
    |> Enum.into(%{})
  end

  defp get_named_action_constants(_trigger_type, _recipient), do: %{}
end
