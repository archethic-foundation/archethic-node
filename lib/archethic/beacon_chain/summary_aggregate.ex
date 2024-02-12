defmodule Archethic.BeaconChain.SummaryAggregate do
  @moduledoc """
  Represents an aggregate of multiple beacon summary from multiple subsets for a given date

  This will help the self-sepair to maintain an aggregated and ordered view of items to synchronize and to resolve
  """

  defstruct [
    :summary_time,
    availability_adding_time: [],
    version: 1,
    replication_attestations: [],
    p2p_availabilities: %{}
  ]

  alias Archethic.Crypto

  alias Archethic.BeaconChain.Subset.P2PSampling
  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.BeaconChain.Summary, as: BeaconSummary

  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  require Logger

  @availability_adding_time :archethic
                            |> Application.compile_env!(Archethic.SelfRepair.Scheduler)
                            |> Keyword.fetch!(:availability_application)

  @type t :: %__MODULE__{
          version: non_neg_integer(),
          summary_time: DateTime.t(),
          replication_attestations: list(ReplicationAttestation.t()),
          availability_adding_time: non_neg_integer() | list(non_neg_integer()),
          p2p_availabilities: %{
            (subset :: binary()) => %{
              node_availabilities: bitstring(),
              node_average_availabilities: list(float()),
              end_of_node_synchronizations: list(Crypto.key()),
              network_patches: list(list(String.t()) | String.t())
            }
          }
        }

  @doc """
  Aggregate a new BeaconChain's summary
  """
  @spec add_summary(t(), BeaconSummary.t()) :: t()
  def add_summary(
        agg = %__MODULE__{},
        %BeaconSummary{
          subset: subset,
          transaction_attestations: transaction_attestations,
          node_availabilities: node_availabilities,
          node_average_availabilities: node_average_availabilities,
          end_of_node_synchronizations: end_of_node_synchronizations,
          availability_adding_time: availability_adding_time,
          network_patches: network_patches
        }
      ) do
    agg =
      Map.update!(
        agg,
        :replication_attestations,
        fn prev ->
          transaction_attestations
          |> Enum.filter(&(ReplicationAttestation.validate(&1) == :ok))
          |> Enum.concat(prev)
        end
      )
      |> Map.update!(:availability_adding_time, &[availability_adding_time | &1])

    if node_availabilities != <<>> or not Enum.empty?(node_average_availabilities) or
         not Enum.empty?(end_of_node_synchronizations) or not Enum.empty?(network_patches) do
      update_in(
        agg,
        [
          Access.key(:p2p_availabilities, %{}),
          Access.key(subset, %{
            node_availabilities: [],
            node_average_availabilities: [],
            end_of_node_synchronizations: [],
            network_patches: []
          })
        ],
        fn prev ->
          add_p2p_availabilities(
            subset,
            prev,
            node_availabilities,
            node_average_availabilities,
            end_of_node_synchronizations,
            network_patches
          )
        end
      )
    else
      agg
    end
  end

  defp add_p2p_availabilities(
         subset,
         map,
         node_availabilities,
         node_average_availabilities,
         end_of_node_synchronizations,
         network_patches
       ) do
    map =
      map
      |> Map.update!(
        :end_of_node_synchronizations,
        &Enum.concat(&1, end_of_node_synchronizations)
      )
      |> Map.update!(
        :network_patches,
        &Enum.concat(&1, [network_patches])
      )

    expected_subset_length = P2PSampling.list_nodes_to_sample(subset) |> Enum.count()

    map =
      if bit_size(node_availabilities) == expected_subset_length do
        map
        |> Map.update!(
          :node_availabilities,
          &Enum.concat(&1, [Utils.bitstring_to_integer_list(node_availabilities)])
        )
      else
        map
      end

    if Enum.count(node_average_availabilities) == expected_subset_length do
      map
      |> Map.update!(
        :node_average_availabilities,
        &Enum.concat(&1, [node_average_availabilities])
      )
    else
      map
    end
  end

  @doc """
  Aggregate summaries batch

  """
  @spec aggregate(t()) :: t()
  def aggregate(agg) do
    agg
    |> Map.update!(:replication_attestations, fn attestations ->
      attestations
      |> ReplicationAttestation.reduce_confirmations()
      |> Enum.sort_by(& &1.transaction_summary.timestamp, {:asc, DateTime})
    end)
    |> Map.update!(:availability_adding_time, fn
      [] ->
        @availability_adding_time

      list ->
        Utils.median(list) |> trunc()
    end)
    |> Map.update!(:p2p_availabilities, fn availabilities_by_subject ->
      availabilities_by_subject
      |> Enum.map(fn {subset, data} ->
        {subset,
         data
         |> Map.update!(:node_availabilities, &aggregate_node_availabilities/1)
         |> Map.update!(:node_average_availabilities, &aggregate_node_average_availabilities/1)
         |> Map.update!(:end_of_node_synchronizations, &Enum.uniq/1)
         |> Map.update!(:network_patches, &aggregate_network_patches(&1, subset))}
      end)
      |> Enum.into(%{})
    end)
  end

  @doc """
  Filter replication attestations list of a summary to keep only the one that reached the
  minimum confirmations threshold and return the refused ones
  """
  @spec filter_reached_threshold(t()) :: {t(), list(ReplicationAttestation.t())}
  def filter_reached_threshold(aggregate = %__MODULE__{replication_attestations: attestations}) do
    %{accepted: accepted_attestations, refused: refused_attestations} =
      Enum.reduce(
        attestations,
        %{accepted: [], refused: []},
        fn attestation, acc ->
          if ReplicationAttestation.reached_threshold?(attestation) do
            # Confirmations reached threshold we accept the attestation in the summary
            Map.update!(acc, :accepted, &[attestation | &1])
          else
            # Confirmations didn't reached threshold, we postpone attestation in next summary
            Map.update!(acc, :refused, &[attestation | &1])
          end
        end
      )
      |> Map.update!(:accepted, &Enum.reverse/1)

    filtered_aggregate = Map.put(aggregate, :replication_attestations, accepted_attestations)

    {filtered_aggregate, refused_attestations}
  end

  defp aggregate_node_availabilities(node_availabilities) do
    node_availabilities
    |> Enum.zip()
    |> Enum.map(&Tuple.to_list/1)
    |> Enum.map(fn availabilities ->
      # Get the mode of the availabilities
      frequencies = Enum.frequencies(availabilities)
      online_frequencies = Map.get(frequencies, 1, 0)
      offline_frequencies = Map.get(frequencies, 0, 0)

      if online_frequencies >= offline_frequencies do
        1
      else
        0
      end
    end)
    |> List.flatten()
    |> Enum.map(&<<&1::1>>)
    |> :erlang.list_to_bitstring()
  end

  defp aggregate_node_average_availabilities(avg_availabilities) do
    avg_availabilities
    |> Enum.zip()
    |> Enum.map(&Tuple.to_list/1)
    |> Enum.map(fn avg_availabilities ->
      Float.round(Enum.sum(avg_availabilities) / length(avg_availabilities), 3)
    end)
  end

  defp aggregate_network_patches(network_patches, subset) do
    sampling_nodes = P2PSampling.list_nodes_to_sample(subset)

    network_patches
    |> Enum.filter(&(length(&1) == length(sampling_nodes)))
    |> Enum.zip()
    |> Enum.map(fn network_patches ->
      network_patches
      |> Tuple.to_list()
      |> Enum.dedup()
      |> resolve_patches_conflicts()
    end)
    |> List.flatten()
  end

  defp resolve_patches_conflicts([patch]), do: patch

  defp resolve_patches_conflicts(conflicts_patches) do
    splitted_patches = Enum.map(conflicts_patches, &String.split(&1, "", trim: true))

    # Aggregate the conflicts patch to get a final network patch
    # We can use mean as the outliers will only impact the way a node
    # fetch data. Because we don't if the truth is coming from the outliers
    # or not, the mean will result in the smallest approximation.
    latency_patch =
      splitted_patches
      |> Enum.map(fn d ->
        d
        |> Enum.take(2)
        |> Enum.map(&String.to_integer(&1, 16))
      end)
      |> Enum.zip()
      |> Enum.map_join(fn x ->
        x
        |> Tuple.to_list()
        |> Utils.median()
        |> trunc()
        |> Integer.to_string(16)
      end)

    bandwidth_patch =
      splitted_patches
      |> Enum.map(fn digits ->
        digits
        |> List.last()
        |> String.to_integer(16)
      end)
      |> Utils.median()
      |> trunc()
      |> Integer.to_string(16)

    "#{latency_patch}#{bandwidth_patch}"
  end

  @doc """
  Determine when the aggregate is empty
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{replication_attestations: [], p2p_availabilities: p2p_availabilities})
      when map_size(p2p_availabilities) == 0,
      do: true

  def empty?(%__MODULE__{}), do: false

  @doc """
  Serialize beacon summaries aggregate
  """
  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{
        version: version,
        summary_time: summary_time,
        replication_attestations: attestations,
        p2p_availabilities: p2p_availabilities,
        availability_adding_time: availability_adding_time
      }) do
    nb_attestations = VarInt.from_value(length(attestations))

    attestations_bin =
      attestations
      |> Enum.map(&ReplicationAttestation.serialize/1)
      |> :erlang.list_to_binary()

    p2p_availabilities_bin =
      p2p_availabilities
      |> Enum.map(fn {subset,
                      %{
                        node_availabilities: node_availabilities,
                        node_average_availabilities: node_avg_availabilities,
                        end_of_node_synchronizations: end_of_sync,
                        network_patches: network_patches
                      }} ->
        nb_node_availabilities = VarInt.from_value(bit_size(node_availabilities))

        node_avg_availabilities_bin =
          node_avg_availabilities
          |> Enum.map(fn avg -> trunc(avg * 100) end)
          |> :erlang.list_to_binary()

        nb_end_of_sync = VarInt.from_value(length(end_of_sync))

        end_of_sync_bin = :erlang.list_to_binary(end_of_sync)

        nb_network_patches_bin =
          network_patches
          |> length()
          |> VarInt.from_value()

        network_patches_bin = :erlang.list_to_binary(network_patches)

        <<subset::binary-size(1), nb_node_availabilities::binary, node_availabilities::bitstring,
          node_avg_availabilities_bin::binary, nb_end_of_sync::binary, end_of_sync_bin::binary,
          nb_network_patches_bin::binary, network_patches_bin::binary>>
      end)
      |> :erlang.list_to_bitstring()

    <<version::8, DateTime.to_unix(summary_time)::32, nb_attestations::binary,
      attestations_bin::binary, map_size(p2p_availabilities)::8,
      p2p_availabilities_bin::bitstring, availability_adding_time::16>>
  end

  @doc """
  Deserialize beacon summaries aggregate
  """
  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(<<version::8, timestamp::32, rest::bitstring>>) do
    {nb_attestations, rest} = VarInt.get_value(rest)

    {attestations, <<nb_p2p_availabilities::8, rest::bitstring>>} =
      Utils.deserialize_transaction_attestations(rest, nb_attestations, [])

    {p2p_availabilities, <<availability_adding_time::16, rest::bitstring>>} =
      deserialize_p2p_availabilities(rest, nb_p2p_availabilities, %{})

    {
      %__MODULE__{
        version: version,
        summary_time: DateTime.from_unix!(timestamp),
        replication_attestations: attestations,
        p2p_availabilities: p2p_availabilities,
        availability_adding_time: availability_adding_time
      },
      rest
    }
  end

  defp deserialize_p2p_availabilities(<<>>, _, acc), do: {acc, <<>>}

  defp deserialize_p2p_availabilities(rest, nb_p2p_availabilities, acc)
       when map_size(acc) == nb_p2p_availabilities do
    {acc, rest}
  end

  defp deserialize_p2p_availabilities(
         <<subset::binary-size(1), rest::bitstring>>,
         nb_p2p_availabilities,
         acc
       ) do
    {nb_node_availabilities, rest} = VarInt.get_value(rest)

    <<node_availabilities::bitstring-size(nb_node_availabilities),
      node_avg_availabilities_bin::binary-size(nb_node_availabilities), rest::bitstring>> = rest

    node_avg_availabilities =
      node_avg_availabilities_bin
      |> :erlang.binary_to_list()
      |> Enum.map(fn avg -> avg / 100 end)

    {nb_end_of_sync, rest} = VarInt.get_value(rest)

    {end_of_node_sync, rest} = Utils.deserialize_public_key_list(rest, nb_end_of_sync, [])

    {nb_patches, rest} = VarInt.get_value(rest)
    <<patches_bin::binary-size(nb_patches * 3), rest::bitstring>> = rest

    network_patches =
      for <<patch::binary-size(3) <- patches_bin>> do
        patch
      end

    deserialize_p2p_availabilities(
      rest,
      nb_p2p_availabilities,
      Map.put(
        acc,
        subset,
        %{
          node_availabilities: node_availabilities,
          node_average_availabilities: node_avg_availabilities,
          end_of_node_synchronizations: end_of_node_sync,
          network_patches: network_patches
        }
      )
    )
  end
end
