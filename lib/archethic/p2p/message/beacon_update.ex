defmodule Archethic.P2P.Message.BeaconUpdate do
  @moduledoc """
  Represents a message to get a beacon updates
  """

  @enforce_keys [:transaction_attestations]
  defstruct [:transaction_attestations]

  alias Archethic.BeaconChain.ReplicationAttestation

  @type t :: %__MODULE__{
          transaction_attestations: list(ReplicationAttestation.t())
        }
end
