defmodule Archethic.Contracts.Interpreter.ActionInterpreter do
  @moduledoc false

  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Contract.State
  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.CommonInterpreter
  alias Archethic.Contracts.Interpreter.FunctionKeys
  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.Contracts.Interpreter.Scope
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  # # Module `Contract` is handled differently
  # @modules_whitelisted []

  @doc """
  Parse the given node and return the trigger and the actions block.
  """
  @spec parse(any(), FunctionKeys.t()) ::
          {:ok, Contract.trigger_type(), Macro.t()} | {:error, any(), String.t()}
  def parse({{:atom, "actions"}, _, [keyword, [do: block]]}, functions_keys) do
    trigger_type = extract_trigger(keyword)

    # We only parse the do..end block with the macro.traverse
    # this help us keep a clean accumulator that is used only for scoping.
    actions_ast = parse_block(AST.wrap_in_block(block), functions_keys)

    {:ok, trigger_type, actions_ast}
  catch
    {:error, node} ->
      {:error, node, "unexpected term"}

    {:error, node, reason} ->
      {:error, node, reason}
  end

  def parse(node, _) do
    {:error, node, "unexpected term"}
  end

  @doc """
  Execute actions code and returns either the next transaction or nil
  The "contract" constant is mandatory.
  """
  @spec execute(ast :: any(), constants :: map(), previous_contract_tx :: Transaction.t()) ::
          {Transaction.t() | nil, State.t()}
  def execute(ast, constants, %Transaction{data: %TransactionData{code: code}}) do
    :ok = Macro.validate(ast)

    # initiate a transaction that will be used by the "Contract" module
    initial_next_tx = %Transaction{type: :contract, data: %TransactionData{code: code}}

    constants =
      constants
      |> Map.put(:next_transaction, initial_next_tx)
      |> Map.put(:next_transaction_changed, false)

    Scope.execute(ast, constants)

    state = Scope.read_global([:state])

    # return a next transaction only if it has been modified
    if Scope.read_global([:next_transaction_changed]) do
      {
        Scope.read_global([:next_transaction]),
        state
      }
    else
      {nil, state}
    end
  end

  # ----------------------------------------------------------------------
  #              _            _
  #   _ __  _ __(___   ____ _| |_ ___
  #  | '_ \| '__| \ \ / / _` | __/ _ \
  #  | |_) | |  | |\ V | (_| | ||  __/
  #  | .__/|_|  |_| \_/ \__,_|\__\___|
  #  |_|
  # ----------------------------------------------------------------------
  defp extract_trigger([{{:atom, "triggered_by"}, {{:atom, "transaction"}, _, nil}}]) do
    {:transaction, nil, nil}
  end

  defp extract_trigger([
         {{:atom, "triggered_by"}, {{:atom, "transaction"}, _, nil}},
         {{:atom, "on"}, {{:atom, action_name}, _, args}}
       ]) do
    args =
      case args do
        nil -> []
        _ -> Enum.map(args, fn {{:atom, arg_name}, _, nil} -> arg_name end)
      end

    {:transaction, action_name, args}
  end

  defp extract_trigger([{{:atom, "triggered_by"}, {{:atom, "oracle"}, _, nil}}]) do
    :oracle
  end

  defp extract_trigger([
         {{:atom, "triggered_by"}, {{:atom, "interval"}, _, nil}},
         {{:atom, "at"}, cron_interval}
       ])
       when is_binary(cron_interval) do
    {:interval, cron_interval}
  end

  defp extract_trigger(
         node = [
           {{:atom, "triggered_by"}, {{:atom, "datetime"}, _, nil}},
           {{:atom, "at"}, timestamp}
         ]
       )
       when is_integer(timestamp) do
    case rem(timestamp, 60) do
      0 ->
        datetime = DateTime.from_unix!(timestamp)
        {:datetime, datetime}

      _ ->
        throw({:error, node, "Datetime triggers must be rounded to the minute"})
    end
  end

  defp extract_trigger(node) do
    throw({:error, node, "Invalid trigger"})
  end

  defp parse_block(ast = {:__block__, [], []}, _), do: ast

  defp parse_block(ast, functions_keys) do
    acc = %{
      functions: functions_keys
    }

    {new_ast, _} =
      Macro.traverse(
        ast,
        acc,
        fn node, acc ->
          prewalk(node, acc)
        end,
        fn node, acc ->
          postwalk(node, acc)
        end
      )

    new_ast
  end

  # ----------------------------------------------------------------------
  #                                _ _
  #   _ __  _ __ _____      ____ _| | | __
  #  | '_ \| '__/ _ \ \ /\ / / _` | | |/ /
  #  | |_) | | |  __/\ V  V | (_| | |   <
  #  | .__/|_|  \___| \_/\_/ \__,_|_|_|\_\
  #  |_|
  # ----------------------------------------------------------------------

  # module call
  defp prewalk(
         node =
           {{:., _meta, [{:__aliases__, _, [atom: module_name]}, {:atom, function_name}]}, _,
            args},
         acc
       ) do
    arity =
      if Library.function_tagged_with?(module_name, function_name, :write_contract),
        do: length(args) + 1,
        else: length(args)

    case Library.validate_module_call(module_name, function_name, arity) do
      :ok -> {node, acc}
      {:error, _reason, message} -> throw({:error, node, message})
    end
  end

  defp prewalk(node, acc) do
    CommonInterpreter.prewalk(node, acc)
  end

  # ----------------------------------------------------------------------
  #                   _                 _ _
  #   _ __   ___  ___| |___      ____ _| | | __
  #  | '_ \ / _ \/ __| __\ \ /\ / / _` | | |/ /
  #  | |_) | (_) \__ | |_ \ V  V | (_| | |   <
  #  | .__/ \___/|___/\__| \_/\_/ \__,_|_|_|\_\
  #  |_|
  # ----------------------------------------------------------------------

  defp postwalk(node, acc), do: CommonInterpreter.postwalk(node, acc)
end
