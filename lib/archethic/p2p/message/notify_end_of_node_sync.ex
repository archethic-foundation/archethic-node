defmodule Archethic.P2P.Message.NotifyEndOfNodeSync do
  @moduledoc """
  Represents a message to request to add an information in the beacon chain regarding a node readyness

  This message is used during the node bootstrapping.
  """
  @enforce_keys [:node_public_key, :timestamp]
  defstruct [:node_public_key, :timestamp]

  alias Archethic.Crypto
  alias Archethic.BeaconChain
  alias Archethic.Utils
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message

  @type t :: %__MODULE__{
          node_public_key: Crypto.key(),
          timestamp: DateTime.t()
        }

  @spec process(__MODULE__.t(), Message.metadata()) :: Ok.t()
  def process(%__MODULE__{node_public_key: public_key, timestamp: timestamp}, _) do
    BeaconChain.add_end_of_node_sync(public_key, timestamp)
    %Ok{}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{node_public_key: public_key, timestamp: timestamp}) do
    <<public_key::binary, DateTime.to_unix(timestamp)::32>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {public_key, <<timestamp::32, rest::bitstring>>} = Utils.deserialize_public_key(rest)

    {%__MODULE__{
       node_public_key: public_key,
       timestamp: DateTime.from_unix!(timestamp)
     }, rest}
  end
end
