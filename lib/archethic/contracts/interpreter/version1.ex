defmodule Archethic.Contracts.Interpreter.Version1 do
  @moduledoc false

  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.ContractConditions, as: Conditions

  alias Archethic.TransactionChain.Transaction

  @doc """
  Parse the code and return the parsed contract.
  """
  @spec parse(binary(), {integer(), integer(), integer()}) ::
          {:ok, Contract.t()} | {:error, String.t()}
  def parse(code, {1, 0, 0}) when is_binary(code) do
    {:ok, %Contract{version: {1, 0, 0}}}
  end

  def parse(_, _), do: {:error, "@version not supported"}

  @doc """
  Return true if the given conditions are valid on the given constants
  """
  @spec valid_conditions?(Conditions.t(), map()) :: bool()
  def valid_conditions?(_conditions, _constants) do
    false
  end

  @doc """
  Execute the trigger/action code.
  May return a new transaction or nil
  """
  @spec execute_trigger(Macro.t(), map()) :: Transaction.t() | nil
  def execute_trigger(_ast, _constants) do
    nil
  end
end
