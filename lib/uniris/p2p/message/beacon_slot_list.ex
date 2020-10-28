defmodule Uniris.P2P.Message.BeaconSlotList do
  @moduledoc """
  Represents a message with a list of beacon slots

  This message is used during the SelfRepair mechanism
  """
  defstruct slots: []

  alias Uniris.BeaconChain.Slot

  @type t :: %__MODULE__{
          slots: list(Slot.t())
        }
end
