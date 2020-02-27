defmodule UnirisChain.Transaction.Data.Ledger.Stock do
  @moduledoc """
  Represents a stock or marketplace
  """
  defstruct [:category, :description, :price_policy, :voucher_policy, :pictures, :items]

  alias __MODULE__.Item
  alias __MODULE__.PricePolicy
  alias __MODULE__.VoucherPolicy

  @typedoc """
  List of picture URI representing the stock
  """
  @type pictures :: list(binary())

  @typedoc """
  Identification of the type of stock offered
  """
  @type category_id() :: binary()
  
  @typedoc """
  Stock is composed from:
  - Category: identification of the type of stock offered
  - Price policy: Offer some discount from a threshold
  - Voucher policy: Offer some discount for a given NFT and threshold
  - Pictures: list of URLs of pictures of the items offered
  - Items: list of stock item to offer
  """
  @type t :: %__MODULE__{
          category: category_id(),
          price_policy: PricePolicy.t(),
          voucher_policy: VoucherPolicy.t(),
          pictures: pictures(),
          items: list(Item.t())
        }
end
