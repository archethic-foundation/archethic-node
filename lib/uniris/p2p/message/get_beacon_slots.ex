defmodule Uniris.P2P.Message.GetBeaconSlots do
  @moduledoc """
  Represents a message to request the list of beacon slots for a list of subsets and times

  This message is used during the self-repair mechanism
  """
  @enforce_keys [:subsets_slots]
  defstruct [:subsets_slots]

  @type t :: %__MODULE__{
          subsets_slots: %{(subset :: binary()) => datetimes :: list(DateTime.t())}
        }
end
