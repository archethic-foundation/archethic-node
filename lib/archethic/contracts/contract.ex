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
            conditions: %{
              transaction: %Conditions{},
              inherit: %Conditions{},
              oracle: %Conditions{}
            },
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
          conditions: %{
            transaction: Conditions.t(),
            inherit: Conditions.t(),
            oracle: Conditions.t()
          },
          constants: Constants.t(),
          next_transaction: Transaction.t()
        }

  @doc """
  Create a contract from a transaction
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
  Add a trigger to the contract
  """
  @spec add_trigger(t(), trigger_type(), Macro.t()) :: t()
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
  @spec add_condition(t(), condition(), Conditions.t()) :: t()
  def add_condition(
        contract = %__MODULE__{},
        condition_name,
        conditions = %Conditions{}
      ) do
    Map.update!(contract, :conditions, &Map.put(&1, condition_name, conditions))
  end
end
