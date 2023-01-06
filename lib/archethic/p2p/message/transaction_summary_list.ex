defmodule Archethic.P2P.Message.TransactionSummaryList do
  @moduledoc """
  Represents a message with a list of transaction summary
  """
  defstruct transaction_summaries: []

  alias Archethic.TransactionChain.TransactionSummary
  alias Archethic.Utils.VarInt

  @type t() :: %__MODULE__{
          transaction_summaries: list(TransactionSummary.t())
        }

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{transaction_summaries: transaction_summaries}) do
    transaction_summaries_bin =
      transaction_summaries
      |> Enum.map(&TransactionSummary.serialize/1)
      |> :erlang.list_to_bitstring()

    encoded_transaction_summaries_len = length(transaction_summaries) |> VarInt.from_value()

    <<232::8, encoded_transaction_summaries_len::binary, transaction_summaries_bin::bitstring>>
  end
end
