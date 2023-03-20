defmodule Archethic.P2P.Message.FirstTransactionAddress do
  @moduledoc false
  alias Archethic.Utils

  @enforce_keys [:address, :timestamp]
  defstruct [:address, :timestamp]

  @type t() :: %__MODULE__{
          address: binary(),
          timestamp: DateTime.t()
        }

  @doc """
  Serialize FirstTransactionAddress Struct
  """
  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: address, timestamp: timestamp}) do
    <<address::binary, DateTime.to_unix(timestamp, :millisecond)::64>>
  end

  @doc """
  Deserialize FirstTransactionAddress Struct
  """
  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {address, <<timestamp::64, rest::bitstring>>} = Utils.deserialize_address(rest)

    {%__MODULE__{
       address: address,
       timestamp: DateTime.from_unix!(timestamp, :millisecond)
     }, rest}
  end
end
