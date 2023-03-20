defmodule Archethic.P2P.Message.GenesisAddress do
  @moduledoc """
  Represents a message to first address from the transaction chain
  """
  alias Archethic.Utils

  @enforce_keys [:address, :timestamp]
  defstruct [:address, :timestamp]

  @type t :: %__MODULE__{
          address: binary(),
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
