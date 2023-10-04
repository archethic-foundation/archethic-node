defmodule Archethic.Contracts.Contract.Result.Success do
  @moduledoc """
  This struct holds the data about an execution that was successful
  """
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  @enforce_keys [:next_tx, :next_state_utxo]
  defstruct [:next_tx, :next_state_utxo, logs: []]

  @type t :: %__MODULE__{
          next_tx: Transaction.t(),
          next_state_utxo: nil | UnspentOutput.t(),
          logs: list(String.t())
        }
end
