defmodule UnirisCore.TransactionData.UCOLedger do
  @moduledoc """
  Represents a UCO ledger movement
  """
  defstruct [:fee, transfers: []]

  alias UnirisCore.TransactionData.Transfer

  @typedoc """
  UCO movement is composed from:
  - Fee: End user can specify the fee to use (nodes will check if it's sufficient)
  - Transfers: List of UCO transfers
  """
  @type t :: %__MODULE__{
          fee: float(),
          transfers: list(Transfer.t())
        }
end
