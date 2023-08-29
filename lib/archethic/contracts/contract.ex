defmodule Archethic.Contracts.Contract do
  @moduledoc """
  Represents a smart contract
  """

  alias Archethic.Contracts.ContractConditions, as: Conditions
  alias Archethic.Contracts.ContractConditions.Subjects, as: ConditionsSubjects
  alias Archethic.Contracts.ContractConstants, as: Constants

  alias Archethic.Contracts.Interpreter

  alias Archethic.SharedSecrets

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Recipient

  defstruct triggers: %{},
            functions: %{},
            version: 0,
            conditions: %{},
            constants: %Constants{},
            next_transaction: %Transaction{data: %TransactionData{}}

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

  @type trigger_key() ::
          :oracle
          | {:transaction, nil, nil}
          | {:transaction, String.t(), non_neg_integer()}
          | {:datetime, DateTime.t()}
          | {:interval, String.t()}

  @type condition_key() ::
          :oracle
          | :inherit
          | {:transaction, nil, nil}
          | {:transaction, String.t(), non_neg_integer()}

  @type origin_family :: SharedSecrets.origin_family()

  @type t() :: %__MODULE__{
          triggers: %{
            trigger_key() => %{args: list(binary()), ast: Macro.t()}
          },
          version: integer(),
          conditions: %{
            condition_key() => Conditions.t()
          },
          constants: Constants.t(),
          next_transaction: Transaction.t()
        }

  @doc """
  Create a contract from a transaction. Same `from_transaction/1` but throws if the contract's code is invalid
  """
  @spec from_transaction!(Transaction.t()) :: t()
  def from_transaction!(tx = %Transaction{data: %TransactionData{code: code}})
      when is_binary(code) and code != "" do
    {:ok, contract} = Interpreter.parse(code)

    %__MODULE__{
      contract
      | constants: %Constants{contract: Constants.from_transaction(tx)}
    }
  end

  @doc """
  Create a contract from a transaction
  """
  @spec from_transaction(Transaction.t()) :: {:ok, t()} | {:error, String.t()}
  def from_transaction(tx = %Transaction{data: %TransactionData{code: code}}) do
    case Interpreter.parse(code) do
      {:ok, contract} ->
        contract_with_constants = %__MODULE__{
          contract
          | constants: %Constants{contract: Constants.from_transaction(tx)}
        }

        {:ok, contract_with_constants}

      {:error, _} = e ->
        e
    end
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

  @doc """
  Return the args names for this recipient or nil
  """
  @spec get_trigger_for_recipient(Recipient.t()) :: nil | trigger_key()
  def get_trigger_for_recipient(%Recipient{action: nil, args: nil}), do: {:transaction, nil, nil}

  def get_trigger_for_recipient(%Recipient{action: action, args: args_values}),
    do: {:transaction, action, length(args_values)}
end
