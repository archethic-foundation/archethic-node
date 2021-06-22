defmodule ArchEthic.Contracts.Contract do
  @moduledoc """
  Represents a smart contract
  """

  alias ArchEthic.Contracts.Contract.Conditions
  alias ArchEthic.Contracts.Contract.Constants
  alias ArchEthic.Contracts.Contract.Trigger

  alias ArchEthic.Contracts.Interpreter

  alias ArchEthic.SharedSecrets

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData

  defstruct triggers: [],
            conditions: %{
              transaction: %Conditions{},
              inherit: %Conditions{},
              oracle: %Conditions{}
            },
            constants: %Constants{},
            next_transaction: %Transaction{data: %TransactionData{}}

  @type trigger_type() :: :datetime | :interval | :transaction
  @type condition() :: :transaction | :inherit | :oracle
  @type origin_family :: SharedSecrets.origin_family()

  @type t() :: %__MODULE__{
          triggers: list(Trigger.t()),
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
  @spec add_trigger(t(), Trigger.type(), Keyword.t(), Macro.t()) :: t()
  def add_trigger(
        contract = %__MODULE__{},
        :datetime,
        opts = [at: _datetime = %DateTime{}],
        actions
      ) do
    do_add_trigger(contract, %Trigger{type: :datetime, opts: opts, actions: actions})
  end

  def add_trigger(contract = %__MODULE__{}, :interval, opts = [at: interval], actions)
      when is_binary(interval) do
    do_add_trigger(contract, %Trigger{type: :interval, opts: opts, actions: actions})
  end

  def add_trigger(contract = %__MODULE__{}, :transaction, _, actions) do
    do_add_trigger(contract, %Trigger{type: :transaction, actions: actions})
  end

  def add_trigger(contract = %__MODULE__{}, :oracle, _, actions) do
    do_add_trigger(contract, %Trigger{type: :oracle, actions: actions})
  end

  defp do_add_trigger(contract, trigger = %Trigger{}) do
    Map.update!(contract, :triggers, &(&1 ++ [trigger]))
  end

  @doc """
  Add a condition to the contract
  """
  @spec add_condition(t(), condition(), any()) :: t()
  def add_condition(
        contract = %__MODULE__{conditions: conditions},
        condition_name,
        condition
      )
      when condition_name in [:transaction, :inherit, :oracle] do
    %{contract | conditions: Map.put(conditions, condition_name, condition)}
  end
end
