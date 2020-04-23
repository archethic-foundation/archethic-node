defmodule UnirisCore.BeaconSlot.NodeInfo do
  defstruct [:public_key, :ready?]

  @type t :: %__MODULE__{
          public_key: UnirisCore.Crypto.key(),
          ready?: boolean()
        }
end
