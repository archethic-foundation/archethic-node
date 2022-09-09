defmodule Archethic.P2P.Message.NewBeaconSlot do
  @moduledoc """
  Represents a message for a new beacon slot transaction
  """

  @enforce_keys [:slot]
  defstruct [:slot]

  alias Archethic.BeaconChain.Slot

  @type t :: %__MODULE__{
          slot: Slot.t()
        }
end
