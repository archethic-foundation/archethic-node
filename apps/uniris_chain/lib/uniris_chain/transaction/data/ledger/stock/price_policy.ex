defmodule UnirisChain.Transaction.Data.Ledger.Stock.PricePolicy do
  @moduledoc """
  Represents a price policy to offer a discount based on a price threshold
  """
  @enforce_keys [:threshold, :policy]
  defstruct [:threshold, :policy]

  @typedoc """
  Price threshold where the discount policity will be applied
  """
  @type threshold :: float()

  @typedoc """
  Percentage of discount offered
  """
  @type discount_policy :: float()

  @typedoc """
  Price policy is composed from:
  - Threshold: Price threshold where the discount policy will be applied
  - Policy: Percentage of discount offered
  """
  @type t :: %__MODULE__{
          threshold: threshold(),
          policy: discount_policy()
        }
end
