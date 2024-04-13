defmodule Archethic.P2P.Message.GetLastTransactionAddress do
  @moduledoc """
  Represents a message to request the last transaction address of a chain
  """
  @enforce_keys [:address, :timestamp]
  defstruct [:address, :timestamp]

  alias Archethic.Crypto
  alias Archethic.Utils
  alias Archethic.TransactionChain
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.LastTransactionAddress

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          timestamp: DateTime.t()
        }

  @spec process(__MODULE__.t(), Message.metadata()) :: LastTransactionAddress.t()
  def process(%__MODULE__{address: address, timestamp: timestamp}, _) do
    {address, time} = TransactionChain.get_last_address(address, timestamp)
    %LastTransactionAddress{address: address, timestamp: time}
  end

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
