defmodule Uniris.P2P.Message.AddBeaconSlotProof do
  @moduledoc """
  Represents a message to send a beacon slot proof during the slot consensus and validation
  """

  @enforce_keys [:subset, :digest, :public_key, :signature]
  defstruct [:subset, :digest, :public_key, :signature]

  alias Uniris.Crypto

  @type t :: %__MODULE__{
          subset: binary(),
          digest: binary(),
          public_key: Crypto.key(),
          signature: binary()
        }
end
