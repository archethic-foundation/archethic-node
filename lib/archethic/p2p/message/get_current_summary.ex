defmodule Archethic.P2P.Message.GetCurrentSummary do
  @moduledoc """
  Represents a message to get the current beacon slots for a subset
  """

  @enforce_keys [:subset]
  defstruct [:subset]

  @type t :: %__MODULE__{
          subset: binary()
        }
end
