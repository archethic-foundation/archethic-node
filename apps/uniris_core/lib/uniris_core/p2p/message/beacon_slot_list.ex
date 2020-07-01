defmodule UnirisCore.P2P.Message.BeaconSlotList do
  defstruct slots: []

  alias UnirisCore.BeaconSlot

  @type t :: %__MODULE__{
          slots: list(BeaconSlot.t())
        }
end
