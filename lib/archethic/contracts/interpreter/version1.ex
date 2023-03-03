defmodule Archethic.Contracts.Interpreter.Version1 do
  @moduledoc false

  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.ContractConditions, as: Conditions
  alias Archethic.Contracts.Interpreter

  alias __MODULE__.ActionInterpreter
  alias __MODULE__.ConditionInterpreter
  alias __MODULE__.ConditionValidator

  alias Archethic.TransactionChain.Transaction

  @doc """
  Parse the code and return the parsed contract.
  """
  @spec parse(Macro.t(), integer()) ::
          {:ok, Contract.t()} | {:error, String.t()}
  def parse(ast, version = 1) do
    case parse_contract(ast, %Contract{}) do
      {:ok, contract} ->
        {:ok, %{contract | version: version}}

      {:error, node, reason} ->
        {:error, Interpreter.format_error_reason(node, reason)}
    end
  end

  def parse(_, _), do: {:error, "@version not supported"}

  @doc """
  Return true if the given conditions are valid on the given constants
  """
  @spec valid_conditions?(Conditions.t(), map()) :: bool()
  def valid_conditions?(conditions, constants) do
    ConditionValidator.valid_conditions?(conditions, constants)
  end

  @doc """
  Execute the trigger/action code.
  May return a new transaction or nil
  """
  @spec execute_trigger(Macro.t(), map()) :: Transaction.t() | nil
  def execute_trigger(ast, constants \\ %{}) do
    ActionInterpreter.execute(ast, constants)
  end

  # ------------------------------------------------------------
  #              _            _
  #   _ __  _ __(___   ____ _| |_ ___
  #  | '_ \| '__| \ \ / / _` | __/ _ \
  #  | |_) | |  | |\ V | (_| | ||  __/
  #  | .__/|_|  |_| \_/ \__,_|\__\___|
  #  |_|
  # ------------------------------------------------------------
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
end
