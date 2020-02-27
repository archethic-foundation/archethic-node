defmodule UnirisChain.Transaction.Data.Ledger.Stock.VoucherPolicy do
  @moduledoc """
  Represents a voucher policy to offer a discount based on the transfer of NFT
  """
  @enforce_keys [:voucher, :policy]
  defstruct [:voucher, :policy]

  @typedoc """
  Name of the NFT accepted to offer discount
  """
  @type voucher :: binary()

  @typedoc """
  Percentage of discount offered
  """
  @type discount_policy :: float()

  @typedoc """
  Voucher policy is composed from:
  - Voucher: Name of the NFT accepted to offer discount
  - Policy: Percentage of discount offered
  """
  @type t :: %__MODULE__{
          voucher: voucher(),
          policy: discount_policy()
        }
end
