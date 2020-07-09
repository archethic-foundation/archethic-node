defmodule UnirisCore.P2P.Message.BeaconSlotList do
  @moduledoc """
  Represents a message with a list of beacon slots

  This message is used during the SelfRepair mechanism
  """
  defstruct slots: []

  alias UnirisCore.BeaconSlot

  @type t :: %__MODULE__{
          slots: list(BeaconSlot.t())
        }
end
