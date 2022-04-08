defmodule ArchEthic.P2P.Message.ReplicationAttestation do
  @moduledoc """
  Represents a message with a replication attestation
  """

  use ArchEthic.P2P.Message, message_id: 30

  alias ArchEthic.BeaconChain.ReplicationAttestation

  @enforce_keys [:attestation]
  defstruct [:attestation]

  @type t :: %__MODULE__{
          attestation: ReplicationAttestation.t()
        }

  def encode(%__MODULE__{attestation: attestation}) do
    ReplicationAttestation.serialize(attestation)
  end

  def decode(message) do
    ReplicationAttestation.deserialize(message)
  end

  def process(%__MODULE__{}) do
  end
end
