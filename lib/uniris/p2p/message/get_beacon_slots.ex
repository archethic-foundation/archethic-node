defmodule Uniris.P2P.Message.GetBeaconSlots do
  @moduledoc """
  Represents a message to request the list of beacon slots for a list of subsets and times

  This message is used during the self-repair mechanism
  """
  @enforce_keys [:subsets, :last_sync_date]
  defstruct [:subsets, :last_sync_date]

  @type t :: %__MODULE__{
          subsets: list(binary()),
          last_sync_date: DateTime.t()
        }
end
