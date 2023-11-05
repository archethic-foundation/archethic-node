defmodule Archethic.Contracts.Contract.ActionWithoutTransaction do
  @moduledoc """
  This struct represents a NO-OP, an execution that did not produce a next transaction
  """
  alias Archethic.Contracts.Contract.State

  @enforce_keys [:encoded_state]
  defstruct [:encoded_state, logs: []]

  @type t :: %__MODULE__{
          encoded_state: State.encoded() | nil,
          logs: list(String.t())
        }
end
