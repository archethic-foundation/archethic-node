defmodule Archethic.Contracts.Interpreter.Legacy do
  @moduledoc false

  require Logger

  alias __MODULE__.ActionInterpreter
  alias __MODULE__.ConditionInterpreter

  alias Archethic.Contracts
  alias Archethic.Contracts.InterpretedContract, as: Contract
  alias Archethic.Contracts.Interpreter.Conditions.Subjects, as: ConditionsSubjects
  alias Archethic.Contracts.Interpreter

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  @doc ~S"""
  Parse a smart contract code and return the filtered AST representation.

  The parser uses a whitelist of instructions, the rest will be rejected
  """
  @spec parse(ast :: Macro.t()) :: {:ok, Contract.t()} | {:error, reason :: binary()}
  def parse(ast) do
    case parse_contract(ast, %Contract{}) do
      {:ok, contract} ->
        {:ok, %{contract | version: 0}}

      {:error, {:unexpected_term, ast}} ->
        {:error, Interpreter.format_error_reason(ast, "unexpected term")}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Return true if the given conditions are valid on the given constants
  """
  @spec valid_conditions?(ConditionsSubjects.t(), map()) :: bool()
  def valid_conditions?(conditions, constants) do
    ConditionInterpreter.valid_conditions?(conditions, constants)
  end

  @doc """
  Execute the trigger/action code.
  May return a new transaction or nil
  """
  @spec execute_trigger(
          ast :: Macro.t(),
          constants :: map(),
          previous_contract_tx :: Transaction.t()
        ) :: Transaction.t() | nil
  def execute_trigger(ast, constants, previous_contract_tx) do
    case ActionInterpreter.execute(ast, constants) do
      # contract did not produce a next_tx
      nil -> nil
      # contract produce a next_tx but we need to feed previous values to it
      next_tx_to_prepare -> chain_transaction(previous_contract_tx, next_tx_to_prepare)
    end
  end

  defp parse_contract({:__block__, _, ast}, contract) do
    parse_ast_block(ast, contract)
  end

  defp parse_contract(ast, contract) do
    parse_ast(ast, contract)
  end

  defp parse_ast_block([ast | rest], contract) do
    case parse_ast(ast, contract) do
      {:ok, contract} ->
        parse_ast_block(rest, contract)

      {:error, _} = e ->
        e
    end
  end

  defp parse_ast_block([], contract), do: {:ok, contract}

  defp parse_ast(ast = {{:atom, "condition"}, _, _}, contract) do
    case ConditionInterpreter.parse(ast) do
      {:ok, condition_type, condition} ->
        {:ok, Contract.add_condition(contract, condition_type, condition)}

      {:error, _} = e ->
        e
    end
  end

  defp parse_ast(ast = {{:atom, "actions"}, _, _}, contract) do
    case ActionInterpreter.parse(ast) do
      {:ok, trigger_type, actions} ->
        {:ok, Contract.add_trigger(contract, trigger_type, actions)}

      {:error, _} = e ->
        e
    end
  end

  defp parse_ast(ast, _), do: {:error, {:unexpected_term, ast}}

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
           previous_transaction: prev_tx
         }
       ) do
    %Transaction{data: %TransactionData{ownerships: previous_ownerships}} =
      Contracts.remove_seed_ownership!(prev_tx)

    put_in(
      acc,
      [:next_transaction, Access.key(:data, %{}), Access.key(:ownerships)],
      previous_ownerships
    )
  end

  defp chain_ownerships(acc), do: acc
end
