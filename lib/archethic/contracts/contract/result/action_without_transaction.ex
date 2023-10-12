defmodule Archethic.Contracts.Contract.ActionWithoutTransaction do
  @moduledoc """
  This struct represents a NO-OP, an execution that did not produce a next transaction
  """
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  @enforce_keys [:next_state_utxo]
  defstruct [:next_state_utxo, logs: []]

  @type t :: %__MODULE__{
          next_state_utxo: nil | UnspentOutput.t(),
          logs: list(String.t())
        }
end
