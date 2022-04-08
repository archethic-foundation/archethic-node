defmodule ArchEthic.P2P.Message.BeaconUpdate do
  @moduledoc """
  Represents a message to get a beacon updates
  """

  @enforce_keys [:transaction_attestations]
  defstruct [:transaction_attestations]

  alias ArchEthic.BeaconChain.ReplicationAttestation

  alias ArchEthic.P2P.Message.Error
  alias ArchEthic.P2P.Message.Ok

  alias ArchEthic.PubSub
  alias ArchEthic.Utils

  use ArchEthic.P2P.Message, message_id: 236

  @type t :: %__MODULE__{
          transaction_attestations: list(ReplicationAttestation.t())
        }

  def encode(%__MODULE__{transaction_attestations: transaction_attestations}) do
    transaction_attestations_bin =
      transaction_attestations
      |> Enum.map(&ReplicationAttestation.serialize/1)
      |> :erlang.list_to_bitstring()

    <<length(transaction_attestations)::16, transaction_attestations_bin::bitstring>>
  end

  def decode(<<nb_transaction_attestations::16, rest::bitstring>>) do
    {transaction_attestations, rest} =
      Utils.deserialize_transaction_attestations(rest, nb_transaction_attestations, [])

    {
      %__MODULE__{
        transaction_attestations: transaction_attestations
      },
      rest
    }
  end

  def process(%__MODULE__{transaction_attestations: transaction_attestations}) do
    Enum.reduce_while(transaction_attestations, %Ok{}, fn attestation, acc ->
      case ReplicationAttestation.validate(attestation) do
        :ok ->
          PubSub.notify_replication_attestation(attestation)
          {:cont, acc}

        {:error, :invalid_confirmations_signatures} ->
          {:halt, %Error{reason: :invalid_attestation}}
      end
    end)
  end
end
