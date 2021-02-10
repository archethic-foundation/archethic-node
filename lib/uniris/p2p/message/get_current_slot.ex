defmodule Uniris.P2P.Message.GetCurrentBeaconSlot do
  @moduledoc """
  Represents a message to get the current beacon slot for the given subset
  """

  @enforce_keys [:subset]
  defstruct [:subset]

  @type t :: %__MODULE__{
          subset: binary()
        }
end
