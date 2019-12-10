defmodule UnirisChain.Transaction.Data.Ledger.Transfer do
  @moduledoc """
  Represents any ledger transfer
  """
  defstruct [:to, :amount, :conditions]

  @typedoc """
  Transfer is composed from:
  - to: receiver address of the asseet
  - amount: specify the number of asset to transfer to the recipients
  - conditions: specify to which address the asset can be used
  """
  @type t :: %__MODULE__{
          to: binary(),
          amount: number(),
          conditions: list(binary())
        }
end
