defmodule ArchEthic.P2P.Message.RegisterBeaconUpdates do
  @moduledoc """
  Represents a message to get a beacon updates
  """
  alias Crypto
  @enforce_keys [:nodePublicKey, :subset, :date]
  defstruct [:nodePublicKey, :subset, :date]

  @type t :: %__MODULE__{
          nodePublicKey: Crypto.key(),
          subset: binary(),
          date: DateTime.t()
        }
end
