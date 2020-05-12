defmodule UnirisCore.BeaconSlot.NodeInfo do
  defstruct [:public_key, :ready?, :timestamp]

  @type t :: %__MODULE__{
          public_key: UnirisCore.Crypto.key(),
          ready?: boolean(),
          timestamp: DateTime.t()
        }
end
