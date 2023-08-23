defmodule Archethic.Contracts.Contract do
  @moduledoc """
  Represents a smart contract
  """

  alias Archethic.Contracts.ContractConditions, as: Conditions
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

  @type origin_family :: SharedSecrets.origin_family()

  @type t() :: %__MODULE__{
          triggers: %{
            trigger_type() => Macro.t()
          },
          version: integer(),
          conditions: %{
            transaction: Conditions.t(),
            inherit: Conditions.t(),
            oracle: Conditions.t()
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
  @spec add_trigger(map(), trigger_type(), Macro.t()) :: t()
  def add_trigger(
        contract = %__MODULE__{},
        type,
        actions
      ) do
    Map.update!(contract, :triggers, &Map.put(&1, type, actions))
  end

  @doc """
  Add a condition to the contract
  """
  @spec add_condition(map(), condition_type(), Conditions.t()) :: t()
  def add_condition(
        contract = %__MODULE__{},
        condition_type,
        conditions = %Conditions{}
      ) do
    Map.update!(contract, :conditions, &Map.put(&1, condition_type, conditions))
  end

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
  @spec get_trigger_for_recipient(t(), Recipient.t()) ::
          nil | {:transaction, String.t(), list(String.t())} | {:transaction, nil, nil}
  def get_trigger_for_recipient(_contract, %Recipient{action: nil, args: nil}),
    do: {:transaction, nil, nil}

  def get_trigger_for_recipient(
        %__MODULE__{triggers: triggers},
        %Recipient{
          action: action,
          args: args_values
        }
      ) do
    arity = length(args_values)

    Enum.find(Map.keys(triggers), fn
      {:transaction, ^action, args_names} when length(args_names) == arity -> true
      _ -> false
    end)
  end
end
