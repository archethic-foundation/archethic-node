defmodule Archethic.P2P.Message.RegisterBeaconUpdates do
  @moduledoc """
  Represents a message to get a beacon updates
  """

  alias Archethic.Crypto
  alias Archethic.Utils
  alias Archethic.BeaconChain
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.Ok

  @enforce_keys [:node_public_key, :subset]
  defstruct [:node_public_key, :subset]

  @type t :: %__MODULE__{
          node_public_key: Crypto.key(),
          subset: binary()
        }

  @spec process(__MODULE__.t(), Message.metadata()) :: Ok.t()
  def process(%__MODULE__{node_public_key: node_public_key, subset: subset}, _) do
    BeaconChain.subscribe_for_beacon_updates(subset, node_public_key)
    %Ok{}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{node_public_key: node_public_key, subset: subset}) do
    <<subset::binary-size(1), node_public_key::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<subset::binary-size(1), rest::binary>>) do
    {public_key, rest} = Utils.deserialize_public_key(rest)

    {
      %__MODULE__{
        subset: subset,
        node_public_key: public_key
      },
      rest
    }
  end
end
