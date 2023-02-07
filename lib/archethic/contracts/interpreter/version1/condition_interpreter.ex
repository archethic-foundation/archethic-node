defmodule Archethic.Contracts.Interpreter.Version1.ConditionInterpreter do
  @moduledoc false

  alias Archethic.Contracts.ContractConditions, as: Conditions

  @type condition_type :: :transaction | :inherit | :oracle

  @spec parse(Macro.t()) ::
          {:ok, condition_type(), Conditions.t()} | {:error, reason :: String.t()}
  def parse(_ast) do
    {:ok, :transaction, %Conditions{}}
  end
end
