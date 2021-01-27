defmodule Uniris.P2P.Message.NotifyBeaconSlot do
  @moduledoc """
  Represents a message to notify a summary pool about a beacon slot  
  """

  @enforce_keys [:slot]
  defstruct [:slot]

  alias Uniris.BeaconChain.Slot

  @type t :: %__MODULE__{
          slot: Slot.t()
        }
end
