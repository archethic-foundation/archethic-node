defmodule Archethic.P2P.Message.GetCurrentReplicationAttestations do
  @moduledoc """
  A request to get the replication attestations of current summary
  The nodes receiving this must be elected to store the given subsets
  """

  @enforce_keys [:subsets]
  defstruct [:subsets]

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.Crypto
  alias Archethic.BeaconChain
  alias Archethic.P2P.Message.GetCurrentReplicationAttestationsResponse

  @type t :: %__MODULE__{subsets: list(binary())}

  @spec process(message :: __MODULE__.t(), sender_public_key :: Crypto.key()) ::
          GetCurrentReplicationAttestationsResponse.t()
  def process(%__MODULE__{subsets: subsets}, _) do
    %GetCurrentReplicationAttestationsResponse{
      replication_attestations:
        subsets
        |> Stream.flat_map(&BeaconChain.get_current_summary_replication_attestations/1)
        |> ReplicationAttestation.reduce_confirmations()
        |> Enum.to_list()
    }
  end

  @spec serialize(message :: t()) :: bitstring()
  def serialize(%__MODULE__{subsets: subsets}) do
    subsets_bin = :erlang.list_to_binary(subsets)

    <<length(subsets)::16, subsets_bin::binary>>
  end

  @spec deserialize(bin :: bitstring()) :: {t(), bitstring()}
  def deserialize(<<nb_subsets::16, rest::bitstring>>) do
    {subsets, <<rest::bitstring>>} = deserialize_subsets(rest, nb_subsets, [])

    {%__MODULE__{subsets: subsets}, rest}
  end

  defp deserialize_subsets(rest, 0, acc), do: {Enum.reverse(acc), rest}

  defp deserialize_subsets(<<subset::8, rest::bitstring>>, n, acc) do
    deserialize_subsets(rest, n - 1, [<<subset>> | acc])
  end
end
