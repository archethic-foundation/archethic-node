defmodule Archethic.Contracts.WasmSpec.Function do
  @moduledoc false

  defstruct [:name, :input, :output]

  @type t() :: %__MODULE__{
          name: String.t(),
          input: map(),
          output: String.t() | map()
        }

  @spec cast(String.t(), map()) :: t()
  def cast(name, abi) do
    %__MODULE__{
      name: name,
      input: Map.get(abi, "input", %{}),
      output: Map.get(abi, "output", "")
    }
  end
end
