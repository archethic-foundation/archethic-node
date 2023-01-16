defmodule Archethic.P2P.Message.TransactionSummaryMessage do
  @moduledoc """
  Represents a message with a transaction summary
  """

  alias Archethic.TransactionChain.TransactionSummary
  alias Archethic.Crypto
  alias Archethic.PubSub
  alias Archethic.P2P.Message.Ok

  defstruct transaction_summary: %TransactionSummary{}

  @type t :: %__MODULE__{
          transaction_summary: TransactionSummary.t()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(%__MODULE__{transaction_summary: tx_summary}, _) do
    PubSub.notify_transaction_attestation(tx_summary)

    %Ok{}
  end

  @spec serialize(t()) :: binary()
  def serialize(%__MODULE__{transaction_summary: tx_summary}) do
    TransactionSummary.serialize(tx_summary)
  end

  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(data) do
    {deserialized_msg, rest} = TransactionSummary.deserialize(data)

    {
      from_transaction_summary(deserialized_msg),
      rest
    }
  end

  @spec from_transaction_summary(TransactionSummary.t()) :: t()
  def from_transaction_summary(tx_summary),
    do: %__MODULE__{
      transaction_summary: tx_summary
    }
end
