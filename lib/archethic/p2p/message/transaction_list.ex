defmodule Archethic.P2P.Message.TransactionList do
  @moduledoc """
  Represents a message with a list of transactions
  """
  defstruct transactions: [], more?: false, paging_state: nil

  alias Archethic.TransactionChain.Transaction
  alias Archethic.Utils.VarInt

  @type t :: %__MODULE__{
          transactions: list(Transaction.t()),
          paging_state: nil | binary(),
          more?: boolean()
        }

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{transactions: transactions, more?: false}) do
    transaction_bin =
      transactions
      |> Stream.map(&Transaction.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_bitstring()

    encoded_transactions_length = Enum.count(transactions) |> VarInt.from_value()

    <<251::8, encoded_transactions_length::binary, transaction_bin::bitstring, 0::1>>
  end

  def encode(%__MODULE__{transactions: transactions, more?: true, paging_state: paging_state}) do
    transaction_bin =
      transactions
      |> Stream.map(&Transaction.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_bitstring()

    encoded_transactions_length = Enum.count(transactions) |> VarInt.from_value()

    <<251::8, encoded_transactions_length::binary, transaction_bin::bitstring, 1::1,
      byte_size(paging_state)::8, paging_state::binary>>
  end
end
