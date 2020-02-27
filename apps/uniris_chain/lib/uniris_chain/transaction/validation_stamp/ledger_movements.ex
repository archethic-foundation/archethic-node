defmodule UnirisChain.Transaction.ValidationStamp.LedgerMovements do
  @moduledoc """
  Represents the ledger movements from the transaction's issuer applying the UTXO model with a previous status and a next status
  """

  alias __MODULE__.UTXO

  defstruct [uco: %UTXO{}, nft: nil]

  @typedoc """
  Ledger movements from the transaction's issuer.
  It represents the summary of the UTXO transfer
  - previous: contains the previous unspent outputs sender and the previous balance aggregated between the previous balance + sum of the unspent outputs asset transfered
  - next: the next balance
  """
  @type t :: %__MODULE__{
    uco: UTXO.t(),
    nft: UTXO.t()
  }
end
