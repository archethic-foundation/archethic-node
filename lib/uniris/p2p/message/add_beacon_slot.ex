defmodule Uniris.P2P.Message.AddBeaconSlot do
  @moduledoc """
  Represents a message to send a beacon slot during the slot consensus and validation
  """

  @enforce_keys [:slot, :public_key, :signature]
  defstruct [:slot, :public_key, :signature]

  alias Uniris.Crypto
  alias Uniris.BeaconChain.Slot

  @type t :: %__MODULE__{
          slot: Slot.t(),
          public_key: Crypto.key(),
          signature: binary()
        }
end
