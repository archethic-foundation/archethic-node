defmodule ArchEthic.P2P.Message.RegisterBeaconUpdates do
  @moduledoc """
  Represents a message to get a beacon updates
  """
  alias ArchEthic.BeaconChain
  alias ArchEthic.Crypto
  alias ArchEthic.P2P.Message.Ok
  alias ArchEthic.Utils

  use ArchEthic.P2P.Message, message_id: 19

  @enforce_keys [:node_public_key, :subset]
  defstruct [:node_public_key, :subset]

  @type t :: %__MODULE__{
          node_public_key: Crypto.key(),
          subset: binary()
        }

  def encode(%__MODULE__{node_public_key: node_public_key, subset: subset}) do
    <<subset::binary-size(1), node_public_key::binary>>
  end

  def decode(<<subset::binary-size(1), rest::bitstring>>) do
    {node_public_key, rest} = Utils.deserialize_public_key(rest)

    {
      %__MODULE__{
        node_public_key: node_public_key,
        subset: subset
      },
      rest
    }
  end

  def process(%__MODULE__{node_public_key: node_public_key, subset: subset}) do
    BeaconChain.subscribe_for_beacon_updates(subset, node_public_key)
    %Ok{}
  end
end
