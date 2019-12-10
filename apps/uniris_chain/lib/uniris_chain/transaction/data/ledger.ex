defmodule UnirisChain.Transaction.Data.Ledger do
  @moduledoc """
  Represents transaction ledger movements
  """
  defstruct [:uco, :nft, :stock]

  alias UnirisChain.Transaction.Data.Ledger.UCO
  alias UnirisChain.Transaction.Data.Ledger.NFT
  alias UnirisChain.Transaction.Data.Ledger.Stock

  @typedoc """
  Ledger movements are composed from:
  - UCO: movements of UCO
  - NFT: movements of NFT
  - Stock: stock management updates
  """
  @type t :: %__MODULE__{
          uco: UCO.t(),
          nft: list(NFT.t()),
          stock: list(Stock.t())
        }
end
