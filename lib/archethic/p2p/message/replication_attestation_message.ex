defmodule Archethic.P2P.Message.ReplicationAttestationMessage do
  @moduledoc """
  Represents a message that contains an attestation of a transaction
  replicated with a list of storage nodes confirmations
  """

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.Crypto
  alias Archethic.PubSub
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Error
  alias Archethic.TransactionChain.TransactionSummary

  require Logger

  defstruct replication_attestation: %ReplicationAttestation{}

  @type t :: %__MODULE__{
          replication_attestation: ReplicationAttestation.t()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t() | Error.t()
  def process(
        %__MODULE__{
          replication_attestation:
            attestation = %ReplicationAttestation{
              transaction_summary: %TransactionSummary{
                address: tx_address,
                type: tx_type
              }
            }
        },
        _
      ) do
    case ReplicationAttestation.validate(attestation) do
      :ok ->
        PubSub.notify_replication_attestation(attestation)
        %Ok{}

      {:error, :invalid_confirmations_signatures} ->
        Logger.error("Invalid attestation signatures",
          transaction_address: Base.encode16(tx_address),
          transaction_type: tx_type
        )

        %Error{reason: :invalid_attestation}
    end
  end

  @spec serialize(t()) :: binary()
  def serialize(%__MODULE__{replication_attestation: replication_attestation}) do
    ReplicationAttestation.serialize(replication_attestation)
  end

  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(data) do
    {deserialized_msg, rest} = ReplicationAttestation.deserialize(data)

    {
      from_replication_attestation(deserialized_msg),
      rest
    }
  end

  @spec from_replication_attestation(ReplicationAttestation.t()) :: t()
  def from_replication_attestation(replication_attestation),
    do: %__MODULE__{
      replication_attestation: replication_attestation
    }
end
