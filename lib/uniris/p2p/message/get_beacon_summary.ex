defmodule Uniris.P2P.Message.GetBeaconSummary do
  @moduledoc """
  Represents a message to request a beacon summary for a given subset and a given date

  This message is used during the self-repair mechanism
  """
  @enforce_keys [:subset, :date]
  defstruct [:subset, :date]

  @type t :: %__MODULE__{
          subset: binary(),
          date: DateTime.t()
        }
end
