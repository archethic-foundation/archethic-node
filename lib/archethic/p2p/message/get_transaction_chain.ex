defmodule Archethic.P2P.Message.GetTransactionChain do
  @moduledoc """
  Represents a message to request an entire transaction chain
  """
  @enforce_keys [:address]
  defstruct [:address, :paging_state, order: :asc]

  alias Archethic.Crypto
  alias Archethic.TransactionChain
  alias Archethic.P2P.Message.TransactionList

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          paging_state: nil | binary(),
          order: :desc | :asc
        }

  # paging_state received contains binary offset for next page, to be used for query
  @spec process(__MODULE__.t(), Crypto.key()) :: TransactionList.t()
  def process(
        %__MODULE__{
          address: tx_address,
          paging_state: paging_state,
          order: order
        },
        _
      ) do
    {chain, more?, paging_state} =
      tx_address
      |> TransactionChain.get([], paging_state: paging_state, order: order)

    # empty list for fields/cols to be processed
    # new_page_state contains binary offset for the next page
    %TransactionList{transactions: chain, paging_state: paging_state, more?: more?}
  end
end
