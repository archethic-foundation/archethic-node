defmodule UnirisChain.Transaction.Data.Ledger.UCO do
  @moduledoc """
  Represents a UCO ledger movement
  """
  @enforce_keys [:transfers]
  defstruct [:fee, :transfers]

  alias UnirisChain.Transaction.Data.Ledger.Transfer

  @typedoc """
  UCO movement is composed from:
  - Fee: End user can specify the fee to use (nodes will check if it's sufficient)
  - Transfers: List of UCO transfers
  """
  @type t :: %__MODULE__{
          fee: number(),
          transfers: list(Transfer.t())
        }
end
