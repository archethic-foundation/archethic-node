defmodule UnirisChain.Transaction.Data.Ledger.Stock.Item do
  @moduledoc """
  Represents a item proposed inside a stock
  """
  defstruct [:id, :quantity, :metadata]

  @typedoc """
  Additional information regarding the item
  """
  @type metadata :: map()

  @typedoc """
  Identifier of the item
  """
  @type id :: binary()

  @typedoc """
  Item proposed in a stock
  - ID: Identifier of the item proposed
  - Quantity: Number of items proposed
  - Metadata: Any data provided to qualify the item and helps the purchase
  """
  @type t :: %__MODULE__{
          id: id(),
          quantity: integer(),
          metadata: metadata()
        }
end
