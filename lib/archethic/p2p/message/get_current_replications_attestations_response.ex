defmodule Archethic.P2P.Message.GetCurrentReplicationsAttestationsResponse do
  @moduledoc """
  Represents a message with a list of transaction summary
  """

  @enforce_keys [:replications_attestations, :more?]
  defstruct [:replications_attestations, :more?, :paging_address]

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.Crypto
  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  @type t() :: %__MODULE__{
          replications_attestations: list(ReplicationAttestation.t()),
          more?: boolean(),
          paging_address: nil | Crypto.prepended_hash()
        }

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{
        replications_attestations: replications_attestations,
        more?: more?,
        paging_address: paging_address
      }) do
    replications_attestations_bin =
      replications_attestations
      |> Enum.map(&ReplicationAttestation.serialize/1)
      |> :erlang.list_to_bitstring()

    encoded_replications_attestations_len =
      length(replications_attestations) |> VarInt.from_value()

    encoded_more =
      if more? do
        <<1::1>>
      else
        <<0::1>>
      end

    encoded_paging_address =
      case paging_address do
        nil ->
          <<0::1>>

        _ ->
          <<1::1, paging_address::binary>>
      end

    <<encoded_replications_attestations_len::binary, replications_attestations_bin::bitstring,
      encoded_more::bitstring, encoded_paging_address::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {count, rest} = rest |> VarInt.get_value()

    {replications_attestations, <<more_bit::1, paging_address_bit::1, rest::bitstring>>} =
      deserialize_list(rest, count, [])

    more? = more_bit == 1

    {paging_address, rest} =
      if paging_address_bit == 1 do
        Utils.deserialize_address(rest)
      else
        {nil, rest}
      end

    {
      %__MODULE__{
        replications_attestations: replications_attestations,
        more?: more?,
        paging_address: paging_address
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
