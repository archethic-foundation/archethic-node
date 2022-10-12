defmodule Archethic.P2P.Message.GetBeaconSummariesAggregate do
  @moduledoc """
  Represents a message to get a beacon summary aggregate
  """

  @enforce_keys [:date]
  defstruct [:date]

  @type t :: %__MODULE__{
          date: DateTime.t()
        }
end
