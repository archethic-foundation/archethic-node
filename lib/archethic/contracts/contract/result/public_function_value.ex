defmodule Archethic.Contracts.Contract.PublicFunctionValue do
  @moduledoc false

  @enforce_keys [:value]
  defstruct [:value, logs: []]

  @type t :: %__MODULE__{
          value: any(),
          logs: list(String.t())
        }
end
