defmodule Archethic.P2P.Message.TransactionChainLength do
  @moduledoc """
  Represents a message with the number of transactions from a chain
  """
  defstruct [:length]

  alias Archethic.Utils.VarInt

  @type t :: %__MODULE__{
          length: non_neg_integer()
        }

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{length: length}) do
    encoded_length = length |> VarInt.from_value()
    <<encoded_length::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {length, rest} = rest |> VarInt.get_value()

    {%__MODULE__{
       length: length
     }, rest}
  end
end
