defmodule Archethic.Contracts.Contract.ConditionAccepted do
  @moduledoc false

  defstruct logs: []

  @type t :: %__MODULE__{
          logs: list(String.t())
        }
end
