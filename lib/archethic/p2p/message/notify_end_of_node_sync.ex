defmodule ArchEthic.P2P.Message.NotifyEndOfNodeSync do
  @moduledoc """
  Represents a message to request to add an information in the beacon chain regarding a node readyness

  This message is used during the node bootstrapping.
  """
  @enforce_keys [:node_public_key, :timestamp]
  defstruct [:node_public_key, :timestamp]

  alias ArchEthic.BeaconChain
  alias ArchEthic.Crypto
  alias ArchEthic.Utils

  use ArchEthic.P2P.Message, message_id: 14

  @type t :: %__MODULE__{
          node_public_key: Crypto.key(),
          timestamp: DateTime.t()
        }

  def encode(%__MODULE__{node_public_key: node_public_key, timestamp: timestamp}) do
    <<node_public_key::binary, DateTime.to_unix(timestamp)::32>>
  end

  def decode(message) when is_bitstring(message) do
    {public_key, <<timestamp::32, rest::bitstring>>} = Utils.deserialize_public_key(message)

    {
      %__MODULE__{
        node_public_key: public_key,
        timestamp: DateTime.from_unix!(timestamp)
      },
      rest
    }
  end

  def process(%__MODULE__{node_public_key: node_public_key, timestamp: timestamp}) do
    BeaconChain.add_end_of_node_sync(node_public_key, timestamp)
  end
end
