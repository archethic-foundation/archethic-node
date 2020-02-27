defmodule UnirisChain.Transaction.Data.Ledger.Transfer do
  @moduledoc """
  Represents any ledger transfer
  """
  defstruct [:to, :amount, :conditions]

  @typedoc """
  Recipient address of the ledger transfers
  """
  @type recipient :: binary()

  @typedoc """
  Set of conditions to spent the outputs transactions
  """
  @type conditions :: list(binary())

  @typedoc """
  Transfer is composed from:
  - to: receiver address of the asset
  - amount: specify the number of asset to transfer to the recipients
  - conditions: specify to which address the asset can be used
  """
  @type t :: %__MODULE__{
          to: recipient(),
          amount: float(),
          conditions: conditions()
        }
end
