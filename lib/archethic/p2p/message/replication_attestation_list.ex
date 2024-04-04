defmodule Archethic.P2P.Message.ReplicationAttestationList do
  @moduledoc """
  Represents a message with a list of transaction summary
  """
  defstruct replications_attestations: []

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.Utils.VarInt

  @type t() :: %__MODULE__{
          replications_attestations: list(ReplicationAttestation.t())
        }

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{replications_attestations: replications_attestations}) do
    replications_attestations_bin =
      replications_attestations
      |> Enum.map(&ReplicationAttestation.serialize/1)
      |> :erlang.list_to_bitstring()

    encoded_replications_attestations_len =
      length(replications_attestations) |> VarInt.from_value()

    <<encoded_replications_attestations_len::binary, replications_attestations_bin::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {count, rest} = rest |> VarInt.get_value()

    {replications_attestations, rest} = deserialize_list(rest, count, [])

    {
      %__MODULE__{
        replications_attestations: replications_attestations
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
