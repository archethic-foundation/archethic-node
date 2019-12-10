defmodule UnirisChain.Transaction.Data.Ledger.Stock do
  @moduledoc """
  Represents a stock or marketplace
  """
  defstruct [:category, :description, :price_policy, :voucher_policy, :pictures, :items]

  alias UnirisChain.Transaction.Data.Ledger.Stock.Item
  alias UnirisChain.Transaction.Data.Ledger.Stock.PricePolicy
  alias UnirisChain.Transaction.Data.Ledger.Stock.VoucherPolicy

  @typedoc """
  Stock is composed from:
  - Category: identification of the type of service offered
  - Price policy: Offer some discount from a threshold
  - Voucher policy: Offer some discount for a given NFT and threshold
  - Pictures: list of URLs of pictures of the items offered
  - Items: list of stock item to offer
  """
  @type t :: %__MODULE__{
          category: binary(),
          price_policy: PricePolicy.t(),
          voucher_policy: VoucherPolicy.t(),
          pictures: list(binary()),
          items: list(Item.t())
        }
end
