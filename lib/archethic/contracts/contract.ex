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

  defstruct triggers: %{},
            public_functions: %{},
            private_functions: %{},
            version: 0,
            conditions: %{},
            constants: %Constants{},
            next_transaction: %Transaction{data: %TransactionData{}}

  @type trigger_type() ::
          {:datetime, DateTime.t()} | {:interval, String.t()} | :transaction | :oracle
  @type condition() :: :transaction | :inherit | :oracle
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
  @spec add_condition(map(), condition(), Conditions.t()) :: t()
  def add_condition(
        contract = %__MODULE__{},
        condition_name,
        conditions = %Conditions{}
      ) do
    Map.update!(contract, :conditions, &Map.put(&1, condition_name, conditions))
  end

  @doc """
  Add a public or private function to the contract
  """
  def add_function(
        contract = %__MODULE__{},
        :public,
        function_name,
        ast,
        args
      ) do
    function_key = function_name <> "/" <> Integer.to_string(length(args))
    Map.update!(contract, :public_functions, &Map.put(&1, function_key, %{ast: ast, args: args}))
  end

  def add_function(
        contract = %__MODULE__{},
        :private,
        function_name,
        ast,
        args
      ) do
    function_key = function_name <> "/" <> Integer.to_string(length(args))
    Map.update!(contract, :private_functions, &Map.put(&1, function_key, %{ast: ast, args: args}))
  end
end
