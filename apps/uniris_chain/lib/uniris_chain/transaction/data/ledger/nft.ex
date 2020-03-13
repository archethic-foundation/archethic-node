defmodule UnirisChain.Transaction.Data.Ledger.NFT do
  @moduledoc """
  Represent a NFT (Non Financial Transaction) transfer
  """
  @enforce_keys [:type, :transfers]
  defstruct [:type, :transfers]

  alias UnirisChain.Transaction.Data.Ledger.Transfer

  @typedoc """
  Name of the NFT
  """
  @type nft_type :: binary()

  @typedoc """
  NFT movement is composed from:
  - Type: NFT name
  - Recipients: address which will receive the NFT
  - Amount: number of NFT transfered to the recipients
  - Conditions: List of addresses where the NFT can be spent
  """
  @type t :: %__MODULE__{
          type: nft_type(),
          transfers: list(Transfer.t())
        }
end
