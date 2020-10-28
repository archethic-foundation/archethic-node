defmodule Uniris.P2P.Message.GetBeaconSlots do
  @moduledoc """
  Represents a message to request the list of beacon slots for a given subset and a given last date

  This message is used during the self-repair mechanism
  """
  @enforce_keys [:subset, :last_sync_date]
  defstruct [:subset, :last_sync_date]

  @type t :: %__MODULE__{
          subset: binary(),
          last_sync_date: DateTime.t()
        }
end
