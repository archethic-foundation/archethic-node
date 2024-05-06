defmodule Archethic.P2P.Message.CurrentReplicationAttestations do
  @moduledoc """
  The response message of GetCurrentReplicationAttestations
  """

  @enforce_keys [:replication_attestations]
  defstruct [:replication_attestations]

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.Utils.VarInt

  @type t() :: %__MODULE__{
          replication_attestations: list(ReplicationAttestation.t())
        }

  @spec serialize(message :: t()) :: bitstring()
  def serialize(%__MODULE__{replication_attestations: replication_attestations}) do
    replication_attestations_bin =
      replication_attestations
      |> Enum.map(&ReplicationAttestation.serialize/1)
      |> :erlang.list_to_bitstring()

    encoded_replication_attestations_len = length(replication_attestations) |> VarInt.from_value()

    <<encoded_replication_attestations_len::binary, replication_attestations_bin::bitstring>>
  end

  @spec deserialize(bin :: bitstring()) :: {t(), bitstring()}
  def deserialize(<<rest::bitstring>>) do
    {count, rest} = rest |> VarInt.get_value()

    {replication_attestations, <<rest::bitstring>>} = deserialize_list(rest, count, [])

    {
      %__MODULE__{
        replication_attestations: replication_attestations
      },
      rest
    }
  end

  defp deserialize_list(rest, 0, _acc), do: {[], rest}

  defp deserialize_list(rest, count, acc) when length(acc) == count do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_list(rest, count, acc) do
    {replication_attestation, rest} = ReplicationAttestation.deserialize(rest)
    deserialize_list(rest, count, [replication_attestation | acc])
  end
end
