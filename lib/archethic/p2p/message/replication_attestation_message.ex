defmodule Archethic.P2P.Message.ReplicationAttestationMessage do
  @moduledoc """
  Represents a message that contains an attestation of a transaction
  replicated with a list of storage nodes confirmations
  """

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.PubSub
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Error
  alias Archethic.TransactionChain.TransactionSummary
  alias Archethic.Utils

  require Logger
  require OpenTelemetry.Tracer

  defstruct replication_attestation: %ReplicationAttestation{}

  @type t :: %__MODULE__{
          replication_attestation: ReplicationAttestation.t()
        }

  @spec process(__MODULE__.t(), Message.metadata()) :: Ok.t() | Error.t()
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
        %{trace: trace}
      ) do
    Utils.extract_progagated_context(trace)

    OpenTelemetry.Tracer.with_span "replicate attestation" do
      OpenTelemetry.Tracer.set_attribute(
        "node",
        P2P.get_node_info() |> Node.endpoint()
      )

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
