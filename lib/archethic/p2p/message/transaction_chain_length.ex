defmodule Archethic.P2P.Message.TransactionChainLength do
  @moduledoc """
  Represents a message with the number of transactions from a chain
  """
  defstruct [:length]

  alias Archethic.Utils.VarInt

  @type t :: %__MODULE__{
          length: non_neg_integer()
        }

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{length: length}) do
    encoded_length = length |> VarInt.from_value()
    <<245::8, encoded_length::binary>>
  end
end
