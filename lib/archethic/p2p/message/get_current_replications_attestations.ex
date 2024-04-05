defmodule Archethic.P2P.Message.GetCurrentReplicationsAttestations do
  @moduledoc """
  Represents a message to get the current beacon slots for a subset
  """

  @enforce_keys [:subsets]
  defstruct [:subsets, :paging_address]

  alias Archethic.Crypto
  alias Archethic.BeaconChain.Slot
  alias Archethic.BeaconChain.Subset
  alias Archethic.P2P.Message.GetCurrentReplicationsAttestationsResponse
  alias Archethic.Utils

  @paging_size 100
  @type t :: %__MODULE__{
          subsets: list(binary()),
          paging_address: nil | Crypto.prepended_hash()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: GetCurrentReplicationsAttestationsResponse.t()
  def process(%__MODULE__{subsets: subsets, paging_address: paging_address}, _) do
    replications_attestations =
      Enum.flat_map(subsets, fn subset ->
        %Slot{transaction_attestations: replication_attestations} =
          Subset.get_current_slot(subset)

        replication_attestations
      end)

    offseted_replications_attestations =
      case paging_address do
        nil ->
          replications_attestations

        _ ->
          replications_attestations
          |> Enum.drop_while(&(&1.transaction_summary.address != paging_address))
          |> Enum.drop(1)
      end

    limited_replications_attestations =
      offseted_replications_attestations |> Enum.take(@paging_size)

    {more?, returned_paging_address} =
      if Enum.count(offseted_replications_attestations) > @paging_size do
        {true, List.last(limited_replications_attestations)}
      else
        {false, nil}
      end

    %GetCurrentReplicationsAttestationsResponse{
      replications_attestations: limited_replications_attestations,
      more?: more?,
      paging_address: returned_paging_address
    }
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{subsets: subsets, paging_address: paging_address}) do
    subsets_bin = :erlang.list_to_binary(subsets)

    paging_address_bin =
      case paging_address do
        nil ->
          <<0::1>>

        _ ->
          <<1::1, paging_address::binary>>
      end

    <<length(subsets)::16, subsets_bin::binary, paging_address_bin::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<nb_subsets::16, rest::bitstring>>) do
    {subsets, <<paging_address_bit::1, rest::bitstring>>} =
      deserialize_subsets(rest, nb_subsets, [])

    {paging_address, rest} =
      if paging_address_bit == 1 do
        Utils.deserialize_address(rest)
      else
        {nil, rest}
      end

    {%__MODULE__{subsets: subsets, paging_address: paging_address}, rest}
  end

  defp deserialize_subsets(rest, 0, acc), do: {Enum.reverse(acc), rest}

  defp deserialize_subsets(<<subset::8, rest::bitstring>>, n, acc) do
    deserialize_subsets(rest, n - 1, [<<subset>> | acc])
  end
end
