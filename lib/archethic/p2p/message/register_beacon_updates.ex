defmodule ArchEthic.P2P.Message.RegisterBeaconUpdates do
  @moduledoc """
  Represents a message to get a beacon updates
  """
  alias ArchEthic.Crypto
  @enforce_keys [:node_public_key, :subset]
  defstruct [:node_public_key, :subset]

  @type t :: %__MODULE__{
          node_public_key: Crypto.key(),
          subset: binary()
        }
end
