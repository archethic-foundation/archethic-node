defmodule ArchEthic.P2P.Message.RegisterBeaconUpdates do
  @moduledoc """
  Represents a message to get a beacon updates
  """
  alias ArchEthic.Crypto
  @enforce_keys [:nodePublicKey, :subset]
  defstruct [:nodePublicKey, :subset]

  @type t :: %__MODULE__{
          nodePublicKey: Crypto.key(),
          subset: binary()
        }
end
