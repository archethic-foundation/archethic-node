defmodule UnirisChain.Transaction.Data.Ledger.Stock.PricePolicy do
  @moduledoc """
  Represents a price policy to offer a discount based on a price threshold
  """
  @enforce_keys [:threshold, :policy]
  defstruct [:threshold, :policy]

  @typedoc """
  Price policy is composed from:
  - Threshold: Price threshold where the discount policy will be applied
  - Policy: Percentage of discount offered
  """
  @type t :: %__MODULE__{
          threshold: number(),
          policy: number()
        }
end
