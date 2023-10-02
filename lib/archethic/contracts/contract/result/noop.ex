defmodule Archethic.Contracts.Contract.Result.Noop do
  @moduledoc """
  This struct represents a NO-OP, an execution that did not produce a next transaction
  """
  alias Archethic.Contracts.State

  @enforce_keys [:next_state]
  defstruct [:next_state, logs: []]

  @type t :: %__MODULE__{
          next_state: State.t(),
          logs: list(String.t())
        }
end
