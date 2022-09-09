defmodule Archethic.P2P.Message.GetCurrentSummaries do
  @moduledoc """
  Represents a message to get the current beacon slots for a subset
  """

  @enforce_keys [:subsets]
  defstruct [:subsets]

  @type t :: %__MODULE__{
          subsets: list(binary())
        }
end
