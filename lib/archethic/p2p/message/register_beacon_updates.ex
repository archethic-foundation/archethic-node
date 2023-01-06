defmodule Archethic.P2P.Message.RegisterBeaconUpdates do
  @moduledoc """
  Represents a message to get a beacon updates
  """

  alias Archethic.Crypto
  alias Archethic.BeaconChain
  alias Archethic.P2P.Message.Ok

  @enforce_keys [:node_public_key, :subset]
  defstruct [:node_public_key, :subset]

  @type t :: %__MODULE__{
          node_public_key: Crypto.key(),
          subset: binary()
        }

  def encode(%__MODULE__{node_public_key: node_public_key, subset: subset}) do
    <<29::8, subset::binary-size(1), node_public_key::binary>>
  end

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(%__MODULE__{node_public_key: node_public_key, subset: subset}, _) do
    BeaconChain.subscribe_for_beacon_updates(subset, node_public_key)
    %Ok{}
  end
end
