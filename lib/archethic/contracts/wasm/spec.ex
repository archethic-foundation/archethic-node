defmodule Archethic.Contracts.WasmSpec do
  alias Archethic.Contracts.WasmTrigger

  defstruct [:version, triggers: [], public_functions: []]

  def cast(%{
        "version" => version,
        "triggers" => triggers,
        "publicFunctions" => public_functions
      }) do
    %__MODULE__{
      version: version,
      triggers: Enum.map(triggers, &WasmTrigger.cast/1),
      public_functions: public_functions
    }
  end
end
