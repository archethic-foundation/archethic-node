defmodule UnirisChain.Transaction.Data.Ledger.Stock.Item do
  @moduledoc """
  Represents a item proposed inside a stock
  """
  defstruct [:id, :quantity, :metadata]

  @typedoc """
  Item proposed in a stock
  - ID: Identifier of the item proposed
  - Quantity: Number of items proposed
  - Metadata: Any data provided to qualify the item and helps the purchase
  """
  @type t :: %__MODULE__{
          id: binary(),
          quantity: integer(),
          metadata: map()
        }
end
