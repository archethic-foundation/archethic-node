defmodule Archethic.Contracts.WasmSpec.Function do
  @moduledoc false

  defstruct [:name, :input]

  @type t() :: %__MODULE__{
          name: String.t(),
          input: map()
        }

  @spec cast(String.t(), map()) :: t()
  def cast(name, abi) do
    %__MODULE__{
      name: name,
      input: Map.get(abi, "input", %{})
    }
  end
end
