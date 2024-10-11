defmodule Archethic.Contracts.WasmSpec.Trigger do
  @moduledoc false

  defstruct [:name, :input, :type]

  @type t() :: %__MODULE__{
          name: String.t(),
          input: map(),
          type: :transaction | :oracle | {:interval, String.t()} | {:datetime, DateTime.t()}
        }

  @spec cast(String.t(), map()) :: t()
  def cast(name, abi) do
    %__MODULE__{
      name: name,
      type: get_trigger_type(abi),
      input: Map.get(abi, "input", %{})
    }
  end

  defp get_trigger_type(abi) do
    case Map.get(abi, "triggerType") do
      "transaction" ->
        :transaction

      "oracle" ->
        :oracle

      "interval" ->
        {:interval, Map.get(abi, "triggerArgument")}

      "datetime" ->
        {:datetime, Map.get(abi, "triggerArgument")}
    end
  end
end
