defmodule UnirisCore.Transaction.ValidationStamp.LedgerMovements.UTXO do
  @moduledoc """
  Represents the UTXO model for a ledger with a previous status and a next status
  """

  defstruct previous: %{from: [], amount: 0}, next: 0

  @type balance :: float()
  @type utxo_senders :: list(binary())

  @type previous_ledger_summary() :: %{
          from: utxo_senders(),
          amount: balance()
        }

  @typedoc """
  It represents the summary of the UTXO transfer
  - previous: contains the previous unspent outputs sender and the previous balance aggregated between the previous balance + sum of the unspent outputs asset transfered
  - next: the next balance
  """
  @type t :: %__MODULE__{
          previous: previous_ledger_summary(),
          next: balance()
        }
end
