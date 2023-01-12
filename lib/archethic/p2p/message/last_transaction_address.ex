defmodule Archethic.P2P.Message.LastTransactionAddress do
  @moduledoc """
  Represents a message with the last address key from a transaction chain
  """
  @enforce_keys [:address]
  defstruct [:address, :timestamp]

  alias Archethic.Crypto
  alias Archethic.Utils

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          timestamp: DateTime.t()
        }

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: address, timestamp: timestamp}) do
    <<address::binary, DateTime.to_unix(timestamp, :millisecond)::64>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {address, <<timestamp::64, rest::bitstring>>} = Utils.deserialize_address(rest)

    {%__MODULE__{
       address: address,
       timestamp: DateTime.from_unix!(timestamp, :millisecond)
     }, rest}
  end
end
