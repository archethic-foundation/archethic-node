defmodule Uniris.P2P.Message.GetBeaconSlot do
  @moduledoc """
  Represents a message to fetch a beacon slot for a given subset and time  
  """

  @enforce_keys [:subset, :slot_time]
  defstruct [:subset, :slot_time]

  @type t :: %__MODULE__{
          subset: binary(),
          slot_time: DateTime.t()
        }
end
