defmodule Archethic.Contracts.Interpreter do
  @moduledoc false

  require Logger

  alias __MODULE__.Legacy
  alias __MODULE__.ActionInterpreter
  alias __MODULE__.ConditionInterpreter
  alias __MODULE__.ConditionValidator

  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.ContractConditions, as: Conditions
  alias Archethic.Contracts.ContractConstants, as: Constants

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  @type version() :: integer()
  @type execute_opts :: [skip_inherit_check?: boolean()]

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

        {:error, {[line: line, column: column], _msg_info, _token}} ->
          {:error, "Parse error at line #{line} column #{column}"}
      end

    :telemetry.execute([:archethic, :contract, :parsing], %{
      duration: System.monotonic_time() - start
    })

    result
  end

  @doc """
  Parse a transaction and return a contract.
  This return a filled contract structure or an human-readable error.
  """
  @spec parse_transaction(Transaction.t()) :: {:ok, Contract.t()} | {:error, String.t()}
  def parse_transaction(contract_tx = %Transaction{data: %TransactionData{code: code}}) do
    case parse(code) do
      {:ok, contract} ->
        {:ok,
         %Contract{
           contract
           | constants: %Constants{contract: Constants.from_transaction(contract_tx)}
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sanitize code takes care of converting atom to {:atom, bin()}.
  This way the user cannot create atoms at all. (which is mandatory to avoid atoms-table exhaustion)
  """
  @spec sanitize_code(binary()) :: {:ok, Macro.t()} | {:error, any()}
  def sanitize_code(code) when is_binary(code) do
    code
    |> String.trim()
    |> Code.string_to_quoted(static_atoms_encoder: &atom_encoder/2)
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
  Execute the trigger/action code.
  May return a new transaction or nil
  """
  @spec execute_trigger_code(version(), Macro.t(), map()) :: Transaction.t() | nil
  def execute_trigger_code(0, ast, constants) do
    Legacy.execute_trigger(ast, constants)
  end

  def execute_trigger_code(1, ast, constants) do
    ActionInterpreter.execute(ast, constants)
  end

  @doc """
  Execution the given contract's trigger.
  Checks all conditions block.

  `maybe_tx` must be
    - the incoming transaction when trigger_type: transaction
    - the oracle transaction when trigger_type: oracle
    - nil for the other trigger_types

  /!\ The transaction returned is not complete, only the `type` and `data` are filled-in.
  """
  @spec execute(
          Contract.trigger_type(),
          Contract.t(),
          nil | Transaction.t(),
          execute_opts()
        ) ::
          {:ok, nil | Transaction.t()}
          | {:error,
             :invalid_triggers_execution
             | :invalid_transaction_constraints
             | :invalid_oracle_constraints
             | :invalid_inherit_constraints}
  def execute(
        trigger_type,
        contract = %Contract{triggers: triggers},
        maybe_tx,
        opts \\ []
      ) do
    case triggers[trigger_type] do
      nil ->
        {:error, :invalid_triggers_execution}

      trigger_code ->
        do_execute(
          trigger_type,
          trigger_code,
          contract,
          maybe_tx,
          contract,
          opts
        )
    end
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

  # ------------------------------------------------------------
  #              _            _
  #   _ __  _ __(___   ____ _| |_ ___
  #  | '_ \| '__| \ \ / / _` | __/ _ \
  #  | |_) | |  | |\ V | (_| | ||  __/
  #  | .__/|_|  |_| \_/ \__,_|\__\___|
  #  |_|
  # ------------------------------------------------------------

  defp do_execute(
         :transaction,
         trigger_code,
         contract,
         incoming_tx = %Transaction{},
         %Contract{
           version: version,
           conditions: conditions,
           constants: %Constants{
             contract: contract_constants
           }
         },
         opts
       ) do
    constants = %{
      "transaction" => Constants.from_transaction(incoming_tx),
      "contract" => contract_constants
    }

    if valid_conditions?(version, conditions.transaction, constants) do
      case execute_trigger(version, trigger_code, contract, incoming_tx) do
        nil ->
          {:ok, nil}

        next_tx ->
          if valid_inherit_condition?(contract, next_tx, opts) do
            {:ok, next_tx}
          else
            {:error, :invalid_inherit_constraints}
          end
      end
    else
      {:error, :invalid_transaction_constraints}
    end
  end

  defp do_execute(
         :oracle,
         trigger_code,
         contract,
         oracle_tx = %Transaction{},
         %Contract{
           version: version,
           conditions: conditions,
           constants: %Constants{
             contract: contract_constants
           }
         },
         opts
       ) do
    constants = %{
      "transaction" => Constants.from_transaction(oracle_tx),
      "contract" => contract_constants
    }

    if valid_conditions?(version, conditions.oracle, constants) do
      case execute_trigger(version, trigger_code, contract, oracle_tx) do
        nil ->
          {:ok, nil}

        next_tx ->
          if valid_inherit_condition?(contract, next_tx, opts) do
            {:ok, next_tx}
          else
            {:error, :invalid_inherit_constraints}
          end
      end
    else
      {:error, :invalid_oracle_constraints}
    end
  end

  defp do_execute(
         _trigger_type,
         trigger_code,
         contract,
         nil,
         %Contract{version: version},
         opts
       ) do
    case execute_trigger(version, trigger_code, contract) do
      nil ->
        {:ok, nil}

      next_tx ->
        if valid_inherit_condition?(contract, next_tx, opts) do
          {:ok, next_tx}
        else
          {:error, :invalid_inherit_constraints}
        end
    end
  end

  defp execute_trigger(
         version,
         trigger_code,
         contract,
         maybe_tx \\ nil
       ) do
    constants_trigger = %{
      "transaction" =>
        case maybe_tx do
          nil -> nil
          tx -> Constants.from_transaction(tx)
        end,
      "contract" => contract.constants.contract
    }

    case execute_trigger_code(version, trigger_code, constants_trigger) do
      nil ->
        # contract did not produce a next_tx
        nil

      next_tx_to_prepare ->
        # contract produce a next_tx but we need to feed previous values to it
        chain_transaction(
          Constants.to_transaction(contract.constants.contract),
          next_tx_to_prepare
        )
    end
  end

  defp valid_inherit_condition?(
         %Contract{
           version: version,
           conditions: %{inherit: condition_inherit},
           constants: %{contract: contract_constants}
         },
         next_tx,
         opts
       ) do
    if Keyword.get(opts, :skip_inherit_check?, false) do
      true
    else
      constants_inherit = %{
        "previous" => contract_constants,
        "next" => Constants.from_transaction(next_tx)
      }

      valid_conditions?(version, condition_inherit, constants_inherit)
    end
  end

  # -----------------------------------------
  # chain next tx
  # -----------------------------------------
  defp chain_transaction(previous_transaction, next_transaction) do
    %{next_transaction: next_tx} =
      %{next_transaction: next_transaction, previous_transaction: previous_transaction}
      |> chain_type()
      |> chain_code()
      |> chain_ownerships()

    next_tx
  end

  defp chain_type(
         acc = %{
           next_transaction: %Transaction{type: nil},
           previous_transaction: _
         }
       ) do
    put_in(acc, [:next_transaction, Access.key(:type)], :contract)
  end

  defp chain_type(acc), do: acc

  defp chain_code(
         acc = %{
           next_transaction: %Transaction{data: %TransactionData{code: ""}},
           previous_transaction: %Transaction{data: %TransactionData{code: previous_code}}
         }
       ) do
    put_in(acc, [:next_transaction, Access.key(:data, %{}), Access.key(:code)], previous_code)
  end

  defp chain_code(acc), do: acc

  defp chain_ownerships(
         acc = %{
           next_transaction: %Transaction{data: %TransactionData{ownerships: []}},
           previous_transaction: %Transaction{
             data: %TransactionData{ownerships: previous_ownerships}
           }
         }
       ) do
    put_in(
      acc,
      [:next_transaction, Access.key(:data, %{}), Access.key(:ownerships)],
      previous_ownerships
    )
  end

  defp chain_ownerships(acc), do: acc

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
    case parse_ast_block(ast, %Contract{}) do
      {:ok, contract} ->
        {:ok, %{contract | version: 1}}

      {:error, node, reason} ->
        {:error, format_error_reason(node, reason)}
    end
  end

  defp parse_contract(_version, _ast) do
    {:error, "@version not supported"}
  end

  defp parse_ast_block([ast | rest], contract) do
    case parse_ast(ast, contract) do
      {:ok, contract} ->
        parse_ast_block(rest, contract)

      {:error, _, _} = e ->
        e
    end
  end

  defp parse_ast_block([], contract), do: {:ok, contract}

  defp parse_ast(ast = {{:atom, "condition"}, _, _}, contract) do
    case ConditionInterpreter.parse(ast) do
      {:ok, condition_type, condition} ->
        {:ok, Contract.add_condition(contract, condition_type, condition)}

      {:error, _, _} = e ->
        e
    end
  end

  defp parse_ast(ast = {{:atom, "actions"}, _, _}, contract) do
    case ActionInterpreter.parse(ast) do
      {:ok, trigger_type, actions} ->
        {:ok, Contract.add_trigger(contract, trigger_type, actions)}

      {:error, _, _} = e ->
        e
    end
  end

  defp parse_ast(ast, _), do: {:error, ast, "unexpected term"}

  # -----------------------------------------
  # contract validation
  # -----------------------------------------

  defp check_contract_blocks({:error, reason}), do: {:error, reason}

  defp check_contract_blocks(
         {:ok, contract = %Contract{triggers: triggers, conditions: conditions}}
       ) do
    cond do
      Map.has_key?(triggers, :transaction) and !Map.has_key?(conditions, :transaction) ->
        {:error, "missing transaction conditions"}

      Map.has_key?(triggers, :oracle) and !Map.has_key?(conditions, :oracle) ->
        {:error, "missing oracle conditions"}

      !Map.has_key?(conditions, :inherit) ->
        {:error, "missing inherit conditions"}

      true ->
        {:ok, contract}
    end
  end
end
