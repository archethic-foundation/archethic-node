defmodule Archethic.P2P.Message.GetTransactionChain do
  @moduledoc """
  Represents a message to request an entire transaction chain
  """
  @enforce_keys [:address]
  defstruct [:address, paging_state: nil, order: :asc]

  alias Archethic.Crypto
  alias Archethic.DB
  alias Archethic.P2P.Message.TransactionList
  alias Archethic.TransactionChain
  alias Archethic.Utils

  @type t :: %__MODULE__{
          address: Crypto.prepended_hash(),
          paging_state: Crypto.prepended_hash() | DateTime.t() | nil,
          order: :desc | :asc
        }

  # paging_state received contains binary offset for next page, to be used for query
  @spec process(__MODULE__.t(), Crypto.key()) :: TransactionList.t()
  def process(%__MODULE__{address: tx_address, paging_state: paging_state, order: order}, _) do
    {chain, more?, paging_address} =
      case TransactionChain.resolve_paging_state(tx_address, paging_state, order) do
        {:ok, paging_address} ->
          DB.get_transaction_chain(tx_address, [], paging_address: paging_address, order: order)

        {:error, _} ->
          {[], false, nil}
      end

    # empty list for fields/cols to be processed
    # new_page_state contains binary offset for the next page
    %TransactionList{transactions: chain, paging_address: paging_address, more?: more?}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: tx_address, paging_state: paging_state, order: order}) do
    order_bit =
      case order do
        :asc -> 0
        :desc -> 1
      end

    paging_state_bin =
      case paging_state do
        nil -> <<0::2>>
        %DateTime{} -> <<1::2, DateTime.to_unix(paging_state)::32>>
        paging_address -> <<2::2, paging_address::binary>>
      end

    <<tx_address::binary, order_bit::1, paging_state_bin::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(<<rest::bitstring>>) do
    {address, <<order_bit::1, rest::bitstring>>} = Utils.deserialize_address(rest)

    {paging_state, rest} =
      case rest do
        <<0::2, rest::bitstring>> -> {nil, rest}
        <<1::2, timestamp::32, rest::bitstring>> -> {DateTime.from_unix!(timestamp), rest}
        <<2::2, rest::bitstring>> -> Utils.deserialize_address(rest)
      end

    order =
      case order_bit do
        0 -> :asc
        1 -> :desc
      end

    {%__MODULE__{address: address, paging_state: paging_state, order: order}, rest}
  end
end
