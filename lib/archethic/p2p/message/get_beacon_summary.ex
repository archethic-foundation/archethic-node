defmodule Archethic.P2P.Message.GetBeaconSummary do
  @moduledoc """
  Represents a message to get a beacon summary
  """

  @enforce_keys [:address]
  defstruct [:address]

  alias Archethic.Crypto

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash()
        }
end
