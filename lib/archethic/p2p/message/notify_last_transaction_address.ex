defmodule ArchEthic.P2P.Message.NotifyLastTransactionAddress do
  @moduledoc """
  Represents a message with to notify a pool of the last address of a previous address
  """
  @enforce_keys [:address, :previous_address, :timestamp]
  defstruct [:address, :previous_address, :timestamp]

  alias ArchEthic.Crypto
  alias ArchEthic.P2P.Message.Ok
  alias ArchEthic.Replication
  alias ArchEthic.Utils

  use ArchEthic.P2P.Message, message_id: 22

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          previous_address: Crypto.versioned_hash(),
          timestamp: DateTime.t()
        }

  def encode(%__MODULE__{
        address: address,
        previous_address: previous_address,
        timestamp: timestamp
      }) do
    <<address::binary, previous_address::binary, DateTime.to_unix(timestamp)::32>>
  end

  def decode(message) when is_bitstring(message) do
    {address, rest} = Utils.deserialize_address(message)
    {previous_address, <<timestamp::32, rest::bitstring>>} = Utils.deserialize_address(rest)

    {
      %__MODULE__{
        address: address,
        previous_address: previous_address,
        timestamp: DateTime.from_unix!(timestamp)
      },
      rest
    }
  end

  def process(%__MODULE__{
        address: address,
        previous_address: previous_address,
        timestamp: timestamp
      }) do
    Replication.acknowledge_previous_storage_nodes(address, previous_address, timestamp)
    %Ok{}
  end
end
