defmodule ArchEthic.P2P.Message.Transaction do
  @moduledoc """
  Represents a transaction
  """

  @enforce_keys :transaction
  defstruct [:transaction]

  alias ArchEthic.TransactionChain.Transaction

  use ArchEthic.P2P.Message, message_id: 252

  @type t :: %__MODULE__{
          transaction: Transaction.t()
        }

  def encode(%__MODULE__{transaction: transaction}) do
    Transaction.serialize(transaction)
  end

  def decode(message) do
    Transaction.deserialize(message)
  end

  def process(%__MODULE__{}) do
  end
end
