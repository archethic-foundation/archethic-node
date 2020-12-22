defmodule Uniris.Contracts.Contract do
  @moduledoc """
  Represents a smart contract
  """

  alias Uniris.Contracts.Contract.Conditions
  alias Uniris.Contracts.Contract.Constants
  alias Uniris.Contracts.Contract.Trigger

  alias Uniris.Contracts.Interpreter

  alias Uniris.SharedSecrets

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData

  defstruct triggers: [],
            conditions: %Conditions{},
            constants: %Constants{},
            next_transaction: %Transaction{data: %TransactionData{}}

  @type trigger_type() :: :datetime | :interval | :transaction
  @type condition() :: :origin_family | :transaction | :inherit
  @type origin_family :: SharedSecrets.origin_family()

  @type t() :: %__MODULE__{
          triggers: list(Trigger.t()),
          conditions: Conditions.t(),
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

  defp do_add_trigger(contract, trigger = %Trigger{}) do
    Map.update!(contract, :triggers, &(&1 ++ [trigger]))
  end

  @doc """
  Add a condition to the contract
  """
  @spec add_condition(t(), condition(), origin_family() | Macro.t()) :: t()
  def add_condition(contract = %__MODULE__{conditions: conditions}, :origin_family, family)
      when is_atom(family) do
    %{contract | conditions: %{conditions | origin_family: family}}
  end

  def add_condition(contract = %__MODULE__{conditions: conditions}, :transaction, macro) do
    %{contract | conditions: %{conditions | transaction: macro}}
  end

  def add_condition(contract = %__MODULE__{conditions: conditions}, :inherit, macro) do
    %{contract | conditions: %{conditions | inherit: macro}}
  end
end
