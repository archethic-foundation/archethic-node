defmodule UnirisCore.TransactionData.Ledger do
  @moduledoc """
  Represents transaction ledger movements
  """
  alias UnirisCore.TransactionData.UCOLedger

  defstruct uco: %UCOLedger{}

  @typedoc """
  Ledger movements are composed from:
  - UCO: movements of UCO
  """
  @type t :: %__MODULE__{
          uco: UCOLedger.t()
        }
end
