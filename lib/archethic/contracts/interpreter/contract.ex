defmodule Archethic.Contracts.InterpretedContract do
  @moduledoc """
  Represents a smart contract
  """

  alias Archethic.Contracts.Contract.State
  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.Conditions
  alias Archethic.Contracts.Interpreter.Conditions.Subjects, as: ConditionsSubjects
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  require Logger

  defstruct triggers: %{},
            functions: %{},
            version: 0,
            conditions: %{},
            state: %{},
            transaction: %Transaction{}

  @type trigger_type() ::
          :oracle
          | {:transaction, nil, nil}
          | {:transaction, String.t(), list(String.t())}
          | {:datetime, DateTime.t()}
          | {:interval, String.t()}

  @type condition_type() ::
          :oracle
          | :inherit
          | {:transaction, nil, nil}
          | {:transaction, String.t(), list(String.t())}

  @type condition_key() ::
          :oracle
          | :inherit
          | Recipient.trigger_key()

  @type t() :: %__MODULE__{
          triggers: %{Recipient.trigger_key() => %{args: list(binary()), ast: Macro.t()}},
          version: integer(),
          conditions: %{condition_key() => Conditions.t()},
          state: State.t(),
          transaction: Transaction.t()
        }

  @doc """
  Create a contract from a transaction. Same `from_transaction/1` but throws if the contract's code is invalid
  """
  @spec from_transaction!(Transaction.t()) :: t()
  def from_transaction!(tx) do
    {:ok, contract} = from_transaction(tx)
    contract
  end

  @doc """
  Create a contract from a transaction
  """
  @spec from_transaction(Transaction.t()) :: {:ok, t()} | {:error, String.t()}
  def from_transaction(tx = %Transaction{data: %TransactionData{code: code}}) do
    case Interpreter.parse(code) do
      {:ok, contract} ->
        state = get_state_from_tx(tx)
        contract = contract |> Map.put(:transaction, tx) |> Map.put(:state, state)
        {:ok, contract}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_state_from_tx(%Transaction{
         validation_stamp: %ValidationStamp{
           ledger_operations: %LedgerOperations{unspent_outputs: utxos}
         }
       }) do
    case Enum.find(utxos, &(&1.type == :state)) do
      %UnspentOutput{encoded_payload: encoded_state} ->
        {state, _rest} = State.deserialize(encoded_state)
        state

      nil ->
        State.empty()
    end
  end

  defp get_state_from_tx(_), do: State.empty()

  @doc """
  Return true if the contract contains at least one trigger
  """
  @spec contains_trigger?(contract :: t()) :: boolean()
  def contains_trigger?(%__MODULE__{triggers: triggers}) do
    non_empty_triggers =
      Enum.reject(triggers, fn {_, %{ast: ast}} -> ast == {:__block__, [], []} end)

    length(non_empty_triggers) > 0
  end

  @doc """
  Add a trigger to the contract
  """
  @spec add_trigger(t(), trigger_type(), any()) :: t()
  def add_trigger(contract, type, actions) do
    trigger_key = get_key(type)
    actions = get_actions(type, actions)

    Map.update!(contract, :triggers, &Map.put(&1, trigger_key, actions))
  end

  @doc """
  Add a condition to the contract
  """
  @spec add_condition(map(), condition_type(), ConditionsSubjects.t()) :: t()
  def add_condition(contract, condition_type, conditions) do
    condition_key = get_key(condition_type)
    conditions = get_conditions(condition_type, conditions)

    Map.update!(contract, :conditions, &Map.put(&1, condition_key, conditions))
  end

  defp get_key({:transaction, action, args}) when is_list(args),
    do: {:transaction, action, length(args)}

  defp get_key(key), do: key

  defp get_conditions({:transaction, _action, args}, conditions) when is_list(args),
    do: %Conditions{args: args, subjects: conditions}

  defp get_conditions(_, conditions), do: %Conditions{subjects: conditions}

  defp get_actions({:transaction, _action, args}, ast) when is_list(args),
    do: %{args: args, ast: ast}

  defp get_actions(_, conditions), do: %{args: [], ast: conditions}

  @doc """
  Add a public or private function to the contract
  """
  @spec add_function(
          contract :: t(),
          function_name :: binary(),
          ast :: any(),
          args :: list(),
          visibility :: atom()
        ) :: t()
  def add_function(
        contract = %__MODULE__{},
        function_name,
        ast,
        args,
        visibility
      ) do
    Map.update!(
      contract,
      :functions,
      &Map.put(&1, {function_name, length(args)}, %{args: args, ast: ast, visibility: visibility})
    )
  end
end
