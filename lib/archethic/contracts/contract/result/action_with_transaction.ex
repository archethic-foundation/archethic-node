defmodule Archethic.Contracts.Contract.ActionWithTransaction do
  @moduledoc """
  This struct holds the data about an execution that was successful
  """
  alias Archethic.Contracts.Contract.State
  alias Archethic.Contracts.Interpreter.Logs
  alias Archethic.TransactionChain.Transaction

  @enforce_keys [:next_tx, :encoded_state]
  defstruct [:next_tx, :encoded_state, logs: []]

  @type t :: %__MODULE__{
          next_tx: Transaction.t(),
          encoded_state: State.encoded() | nil,
          logs: Logs.t()
        }
end
