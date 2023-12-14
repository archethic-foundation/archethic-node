defmodule Archethic.Contracts.Contract.ConditionRejected do
  @moduledoc false

  alias Archethic.Contracts.Interpreter.Logs

  @enforce_keys [:subject]
  defstruct [:subject, :reason, logs: []]

  @type t :: %__MODULE__{
          subject: String.t(),
          reason: nil | String.t(),
          logs: Logs.t()
        }
end
