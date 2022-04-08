defmodule ArchEthic.P2P.Message.TransactionChainLength do
  @moduledoc """
  Represents a message with the number of transactions from a chain
  """
  defstruct [:length]

  @type t :: %__MODULE__{
          length: non_neg_integer()
        }
  use ArchEthic.P2P.Message, message_id: 245

  def encode(%__MODULE__{length: length}) do
    <<length::32>>
  end

  def decode(<<length::32, rest>>) do
    {
      %__MODULE__{length: length},
      rest
    }
  end

  def process(%__MODULE__{}) do
  end
end
