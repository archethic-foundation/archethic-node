defmodule Archethic.P2P.Message.GetTransactionChain do
  @moduledoc """
  Represents a message to request an entire transaction chain
  """
  @enforce_keys [:address]
  defstruct [:address, :paging_state, order: :asc]

  alias Archethic.Crypto
  alias Archethic.TransactionChain
  alias Archethic.P2P.Message.TransactionList
  alias Archethic.Utils

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

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: tx_address, paging_state: nil, order: order}) do
    order_bit =
      case order do
        :asc -> 0
        :desc -> 1
      end

    <<tx_address::binary, order_bit::1, 0::8>>
  end

  def serialize(%__MODULE__{address: tx_address, paging_state: paging_state, order: order}) do
    order_bit =
      case order do
        :asc -> 0
        :desc -> 1
      end

    <<tx_address::binary, order_bit::1, byte_size(paging_state)::8, paging_state::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {address,
     <<order_bit::1, paging_state_size::8, paging_state::binary-size(paging_state_size),
       rest::bitstring>>} = Utils.deserialize_address(rest)

    paging_state =
      case paging_state do
        "" ->
          nil

        _ ->
          paging_state
      end

    order =
      case order_bit do
        0 -> :asc
        1 -> :desc
      end

    {
      %__MODULE__{address: address, paging_state: paging_state, order: order},
      rest
    }
  end
end
