defmodule Archethic.Contracts.Contract.ConditionRejected do
  @moduledoc false

  @enforce_keys [:subject]
  defstruct [:subject, logs: []]

  @type t :: %__MODULE__{
          subject: String.t(),
          logs: list(String.t())
        }
end
