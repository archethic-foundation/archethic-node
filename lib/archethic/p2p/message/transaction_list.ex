defmodule ArchEthic.P2P.Message.TransactionList do
  @moduledoc """
  Represents a message with a list of transactions
  """
  defstruct transactions: []

  alias ArchEthic.TransactionChain.Transaction

  use ArchEthic.P2P.Message, message_id: 251

  @type t :: %__MODULE__{
          transactions: list(Transaction.t())
        }

  def encode(%__MODULE__{transactions: transactions}) do
    transaction_bin =
      transactions
      |> Stream.map(&Transaction.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_bitstring()

    <<Enum.count(transactions)::32, transaction_bin::bitstring>>
  end

  def decode(<<nb_transactions::32, rest::bitstring>>) do
    {transactions, rest} = deserialize_tx_list(rest, nb_transactions, [])

    {
      %__MODULE__{
        transactions: transactions
      },
      rest
    }
  end

  defp deserialize_tx_list(rest, 0, _acc), do: {[], rest}

  defp deserialize_tx_list(rest, nb_transactions, acc) when length(acc) == nb_transactions do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_tx_list(rest, nb_transactions, acc) do
    {tx, rest} = Transaction.deserialize(rest)
    deserialize_tx_list(rest, nb_transactions, [tx | acc])
  end

  def process(%__MODULE__{}) do
  end
end
