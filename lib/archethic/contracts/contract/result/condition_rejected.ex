defmodule Archethic.Contracts.Contract.ConditionRejected do
  @moduledoc false

  @enforce_keys [:subject]
  defstruct [:subject, :msg, logs: []]

  @type t :: %__MODULE__{
          subject: String.t(),
          msg: String.t() | nil,
          logs: list(String.t())
        }
end
