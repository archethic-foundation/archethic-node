defmodule Archethic.P2P.Message.TransactionList do
  @moduledoc """
  Represents a message with a list of transactions
  """
  defstruct transactions: [], more?: false, paging_address: nil

  alias Archethic.TransactionChain.Transaction
  alias Archethic.Utils.VarInt

  @type t :: %__MODULE__{
          transactions: list(Transaction.t()),
          paging_address: nil | binary(),
          more?: boolean()
        }

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{transactions: transactions, more?: false}) do
    transaction_bin =
      transactions
      |> Stream.map(&Transaction.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_bitstring()

    encoded_transactions_length = Enum.count(transactions) |> VarInt.from_value()

    <<encoded_transactions_length::binary, transaction_bin::bitstring, 0::1>>
  end

  def serialize(%__MODULE__{
        transactions: transactions,
        more?: true,
        paging_address: paging_address
      }) do
    transaction_bin =
      transactions
      |> Stream.map(&Transaction.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_bitstring()

    encoded_transactions_length = Enum.count(transactions) |> VarInt.from_value()

    <<encoded_transactions_length::binary, transaction_bin::bitstring, 1::1,
      byte_size(paging_address)::8, paging_address::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {nb_transactions, rest} = rest |> VarInt.get_value()
    {transactions, rest} = deserialize_tx_list(rest, nb_transactions, [])

    case rest do
      <<0::1, rest::bitstring>> ->
        {
          %__MODULE__{transactions: transactions, more?: false},
          rest
        }

      <<1::1, paging_address_size::8, paging_address::binary-size(paging_address_size),
        rest::bitstring>> ->
        {
          %__MODULE__{transactions: transactions, more?: true, paging_address: paging_address},
          rest
        }
    end
  end

  defp deserialize_tx_list(rest, 0, _acc), do: {[], rest}

  defp deserialize_tx_list(rest, nb_transactions, acc) when length(acc) == nb_transactions do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_tx_list(rest, nb_transactions, acc) do
    {tx, rest} = Transaction.deserialize(rest)
    deserialize_tx_list(rest, nb_transactions, [tx | acc])
  end
end
